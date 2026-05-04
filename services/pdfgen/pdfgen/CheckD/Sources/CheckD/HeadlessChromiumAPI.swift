//
//  HeadlessChromiumAPI.swift
//  CheckD
//
//  Сценарий: долгоживущий контейнер с chromedriver; приложение только подключается по HTTP
//  (WebDriver + CDP через AsyncHTTPClient). Одна `Session` = один браузер; очередь с rate-limit
//  сериализует `printPage` по этой сессии. Рестарт браузера раз в ~10 мин: `renewSession()` или `close()` + `openSession`.
//  OOM / рестарт контейнера: `HeadlessChromiumRecoveringSession` — один повтор печати после `renewSession`, если ответ драйвера/сеть указывают на «мёртвую» сессию.
//

import AsyncHTTPClient
import Foundation
import NIOCore

public enum HeadlessChromiumError: Error, Sendable {
    case browserNotFound(searchedPaths: [String])
    case chromedriverNotFound(searchedPaths: [String])
    case urlUnreachable(url: URL, statusCode: Int?)
    case outputDirectoryNotWritable(URL)
    case outputFileNotWritable(URL)
    case webDriverError(status: Int, body: String)
    case webDriverDecodeFailed(body: String)
}

public final class HeadlessChromiumAPI {
    public static let browserPathEnvironmentKey = "CHROME_PATH"
    public static let chromedriverPathEnvironmentKey = "CHROMEDRIVER_PATH"
    /// Базовый URL chromedriver, например `http://chromedriver:9515` (без завершающего `/`).
    public static let chromedriverBaseURLEnvironmentKey = "CHROMEDRIVER_URL"
    
    // MARK: - Долгоживущая сессия (один Chrome, много `printPage` под очередью)
    
    /// Активная WebDriver-сессия к уже запущенному chromedriver.
    public struct Session: Sendable {
        private let driverBaseURL: String
        public let sessionId: String
        private let httpTimeoutSeconds: Int64
        private let pageLoadTimeoutSeconds: Int64
        
        fileprivate init(
            driverBaseURL: String,
            sessionId: String,
            httpTimeoutSeconds: Int64,
            pageLoadTimeoutSeconds: Int64
        ) {
            self.driverBaseURL = driverBaseURL
            self.sessionId = sessionId
            self.httpTimeoutSeconds = httpTimeoutSeconds
            self.pageLoadTimeoutSeconds = pageLoadTimeoutSeconds
        }
        
        /// Таймаут HTTP к chromedriver (и для `preflightURL` к целевой странице снаружи `printPage`).
        public var webDriverHTTPTimeoutSeconds: Int64 { httpTimeoutSeconds }
        
        /// Навигация → ожидание загрузки → PDF в **конкретный** файл (перезапись).
        public func printPage(url: URL, to outputPDF: URL, preflightHTTP: Bool = true) async throws {
            let fm = FileManager.default
            let parent = outputPDF.deletingLastPathComponent()
            guard fm.fileExists(atPath: parent.path),
                  fm.isWritableFile(atPath: parent.path) else {
                throw HeadlessChromiumError.outputFileNotWritable(outputPDF)
            }
            if preflightHTTP {
                try await HeadlessChromiumAPI.preflightURL(url, timeoutSeconds: httpTimeoutSeconds)
            }
            try await HeadlessChromiumAPI.navigate(
                baseURL: driverBaseURL,
                sessionId: sessionId,
                url: url,
                timeoutSeconds: pageLoadTimeoutSeconds
            )
            try await HeadlessChromiumAPI.waitDocumentComplete(
                baseURL: driverBaseURL,
                sessionId: sessionId,
                timeoutSeconds: pageLoadTimeoutSeconds
            )
            let pdfData = try await HeadlessChromiumAPI.printCurrentPageToPDFData(
                baseURL: driverBaseURL,
                sessionId: sessionId,
                timeoutSeconds: pageLoadTimeoutSeconds
            )
            try pdfData.write(to: outputPDF, options: .atomic)
        }
        
        /// `DELETE /session/{id}` — закрыть браузер этой сессии (перед рестартом контейнера или сменой сессии).
        public func close() async {
            await HeadlessChromiumAPI.deleteSession(
                baseURL: driverBaseURL,
                sessionId: sessionId,
                timeoutSeconds: httpTimeoutSeconds
            )
        }
        
        /// Новая WebDriver-сессия у **того же** chromedriver: сначала успешный `openSession`, затем замена `self`, затем `close()` прежней.
        ///
        /// Если `openSession` бросает ошибку, это значение `Session` не меняется. После замены старая сессия закрывается асинхронно через WebDriver.
        public mutating func renewSession(
            browserExecutable: URL? = nil,
            dockerSafe: Bool = false,
            httpTimeoutSeconds overrideHTTPTimeout: Int64? = nil,
            pageLoadTimeoutSeconds overridePageLoadTimeout: Int64? = nil
        ) async throws {
            let newSession = try await HeadlessChromiumAPI.openSession(
                driverBaseURL: driverBaseURL,
                browserExecutable: browserExecutable,
                dockerSafe: dockerSafe,
                httpTimeoutSeconds: overrideHTTPTimeout ?? httpTimeoutSeconds,
                pageLoadTimeoutSeconds: overridePageLoadTimeout ?? pageLoadTimeoutSeconds
            )
            let previous = self
            self = newSession
            await previous.close()
        }
    }
    
    /// `true`, если после **успешного** preflight к целевому URL ошибка почти наверняка из-за chromedriver / мёртвой WebDriver-сессии (OOM, рестарт контейнера, `invalid session id`), а не из-за самой страницы.
    public nonisolated static func errorIndicatesWebDriverSessionOrTransportLikelyDead(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        var chain: Error? = error
        var hops = 0
        while let e = chain, hops < 8 {
            hops += 1
            if let he = e as? HeadlessChromiumError {
                switch he {
                case .urlUnreachable, .outputFileNotWritable, .outputDirectoryNotWritable, .browserNotFound, .chromedriverNotFound:
                    return false
                case .webDriverDecodeFailed:
                    return false
                case .webDriverError(let status, let body):
                    return webDriverHTTPOrBodyIndicatesDeadSession(httpStatus: status, body: body)
                }
            }
            if let url = e as? URLError {
                switch url.code {
                case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed, .timedOut,
                     .cannotLoadFromNetwork, .resourceUnavailable:
                    return true
                default:
                    return false
                }
            }
            chain = (e as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }
    
    /// Актор: одна очередь печати, при «падении» сессии один раз открывает новую (`renewSession`) и повторяет печать.
    public actor HeadlessChromiumRecoveringSession {
        private var session: HeadlessChromiumAPI.Session
        private let browserExecutable: URL?
        private let dockerSafe: Bool
        
        public init(
            session: HeadlessChromiumAPI.Session,
            browserExecutable: URL? = nil,
            dockerSafe: Bool = false
        ) {
            self.session = session
            self.browserExecutable = browserExecutable
            self.dockerSafe = dockerSafe
        }
        
        /// То же, что `HeadlessChromiumAPI.openSession`, но обёртка с авто-восстановлением при печати.
        public static func open(
            driverBaseURL: String? = nil,
            driverPort: Int = 9515,
            browserExecutable: URL? = nil,
            dockerSafe: Bool = false,
            httpTimeoutSeconds: Int64 = 60,
            pageLoadTimeoutSeconds: Int64 = 60
        ) async throws -> HeadlessChromiumRecoveringSession {
            let s = try await HeadlessChromiumAPI.openSession(
                driverBaseURL: driverBaseURL,
                driverPort: driverPort,
                browserExecutable: browserExecutable,
                dockerSafe: dockerSafe,
                httpTimeoutSeconds: httpTimeoutSeconds,
                pageLoadTimeoutSeconds: pageLoadTimeoutSeconds
            )
            return HeadlessChromiumRecoveringSession(session: s, browserExecutable: browserExecutable, dockerSafe: dockerSafe)
        }
        
        /// Preflight (если включён) выполняется **один раз** к целевому URL; повтор только для шагов WebDriver к chromedriver.
        public func printPage(url: URL, to outputPDF: URL, preflightHTTP: Bool = true) async throws {
            if preflightHTTP {
                try await HeadlessChromiumAPI.preflightURL(url, timeoutSeconds: session.webDriverHTTPTimeoutSeconds)
            }
            do {
                try await session.printPage(url: url, to: outputPDF, preflightHTTP: false)
            } catch {
                guard HeadlessChromiumAPI.errorIndicatesWebDriverSessionOrTransportLikelyDead(error) else {
                    throw error
                }
                var s = session
                try await s.renewSession(browserExecutable: browserExecutable, dockerSafe: dockerSafe)
                session = s
                try await session.printPage(url: url, to: outputPDF, preflightHTTP: false)
            }
        }
        
        public func renewSession(
            browserExecutable: URL? = nil,
            dockerSafe: Bool? = nil,
            httpTimeoutSeconds: Int64? = nil,
            pageLoadTimeoutSeconds: Int64? = nil
        ) async throws {
            var s = session
            try await s.renewSession(
                browserExecutable: browserExecutable ?? self.browserExecutable,
                dockerSafe: dockerSafe ?? self.dockerSafe,
                httpTimeoutSeconds: httpTimeoutSeconds,
                pageLoadTimeoutSeconds: pageLoadTimeoutSeconds
            )
            session = s
        }
        
        public func close() async {
            await session.close()
        }
    }
    
    /// Открыть новую WebDriver-сессию у **уже слушающего** chromedriver (`POST /session`).
    public static func openSession(
        driverBaseURL: String? = nil,
        driverPort: Int = 9515,
        browserExecutable: URL? = nil,
        dockerSafe: Bool = false,
        httpTimeoutSeconds: Int64 = 60,
        pageLoadTimeoutSeconds: Int64 = 60
    ) async throws -> Session {
        let base = normalizedDriverBaseURL(explicit: driverBaseURL, driverPort: driverPort)
        let chromeBin: URL
        if let browserExecutable {
            chromeBin = browserExecutable
        } else {
            chromeBin = try resolveBrowserExecutable()
        }
        let sessionBody = try buildNewSessionBody(chromeBinary: chromeBin, dockerSafe: dockerSafe)
        let sessionResp = try await webDriverPOST(
            baseURL: base,
            path: "/session",
            body: sessionBody,
            timeoutSeconds: httpTimeoutSeconds
        )
        let sessionId = try extractSessionId(from: sessionResp)
        return Session(
            driverBaseURL: base,
            sessionId: sessionId,
            httpTimeoutSeconds: httpTimeoutSeconds,
            pageLoadTimeoutSeconds: pageLoadTimeoutSeconds
        )
    }
    
    private static func normalizedDriverBaseURL(explicit: String?, driverPort: Int) -> String {
        let raw = explicit
            ?? ProcessInfo.processInfo.environment[chromedriverBaseURLEnvironmentKey]
            ?? "http://127.0.0.1:\(driverPort)"
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    // MARK: - Пути к бинарникам
    
    public static func defaultBrowserSearchPaths() -> [String] {
        #if os(macOS)
        return [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        ]
        #else
        return [
            "/usr/bin/google-chrome-stable",
            "/usr/bin/google-chrome",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
        ]
        #endif
    }
    
    public static func defaultChromedriverSearchPaths() -> [String] {
        #if os(macOS)
        return [
            "/opt/homebrew/bin/chromedriver",
            "/usr/local/bin/chromedriver",
            "/usr/bin/chromedriver",
        ]
        #else
        return [
            "/usr/bin/chromedriver",
            "/usr/local/bin/chromedriver",
        ]
        #endif
    }
    
    public static func resolveBrowserExecutable(customPath: String? = nil) throws -> URL {
        if let raw = customPath ?? ProcessInfo.processInfo.environment[browserPathEnvironmentKey],
           !raw.isEmpty {
            let url = URL(fileURLWithPath: raw)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        for path in defaultBrowserSearchPaths() where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw HeadlessChromiumError.browserNotFound(searchedPaths: defaultBrowserSearchPaths())
    }
    
    public static func resolveChromedriverExecutable(customPath: String? = nil) throws -> URL {
        if let raw = customPath ?? ProcessInfo.processInfo.environment[chromedriverPathEnvironmentKey],
           !raw.isEmpty {
            let url = URL(fileURLWithPath: raw)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        for path in defaultChromedriverSearchPaths() where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw HeadlessChromiumError.chromedriverNotFound(searchedPaths: defaultChromedriverSearchPaths())
    }
    
    // MARK: - HTTP (AsyncHTTPClient)
    
    public static func preflightURL(_ url: URL, timeoutSeconds: Int64 = 30) async throws {
        var headRequest = HTTPClientRequest(url: url.absoluteString)
        headRequest.method = .HEAD
        headRequest.headers.add(name: "User-Agent", value: "CheckD-HeadlessChromium/1.0")
        let headResponse = try await HTTPClient.shared.execute(headRequest, timeout: .seconds(timeoutSeconds))
        switch headResponse.status.code {
        case 200..<400:
            _ = try? await headResponse.body.collect(upTo: 64)
            return
        case 405:
            break
        default:
            throw HeadlessChromiumError.urlUnreachable(url: url, statusCode: Int(headResponse.status.code))
        }
        var getRequest = HTTPClientRequest(url: url.absoluteString)
        getRequest.method = .GET
        getRequest.headers.add(name: "User-Agent", value: "CheckD-HeadlessChromium/1.0")
        let getResponse = try await HTTPClient.shared.execute(getRequest, timeout: .seconds(timeoutSeconds))
        guard (200..<400).contains(getResponse.status.code) else {
            throw HeadlessChromiumError.urlUnreachable(url: url, statusCode: Int(getResponse.status.code))
        }
        _ = try? await getResponse.body.collect(upTo: 65536)
    }
    
    private nonisolated static func webDriverW3CValueErrorIndicatesDeadSession(_ code: String) -> Bool {
        switch code {
        case "invalid session id", "session not found", "chrome not reachable", "no such window",
             "disconnected", "no such execution context", "target crashed", "tab crashed":
            return true
        default:
            return false
        }
    }
    
    private nonisolated static func webDriverHTTPOrBodyIndicatesDeadSession(httpStatus status: Int, body: String) -> Bool {
        if let data = body.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = root["value"] as? [String: Any],
           let err = value["error"] as? String,
           webDriverW3CValueErrorIndicatesDeadSession(err) {
            return true
        }
        let lower = body.lowercased()
        if lower.contains("invalid session id") || lower.contains("chrome not reachable") { return true }
        if lower.contains("session deleted") || lower.contains("no such session") { return true }
        if status == 404 || status == 408 || status == 410 { return true }
        if status == 500, lower.contains("chrome"), lower.contains("reachable") { return true }
        return false
    }
    
    private static func webDriverPOST(baseURL: String, path: String, body: Data, timeoutSeconds: Int64) async throws -> Data {
        let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        var request = HTTPClientRequest(url: urlString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(body)
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(timeoutSeconds))
        var bodyBuffer = try await response.body.collect(upTo: 32 * 1024 * 1024)
        let data = bodyBuffer.readData(length: bodyBuffer.readableBytes) ?? Data()
        guard (200..<300).contains(response.status.code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw HeadlessChromiumError.webDriverError(status: Int(response.status.code), body: text)
        }
        // W3C: chromedriver иногда отдаёт HTTP 200 с `value.error` (например `invalid session id`).
        if let root = try? parseJSONObject(data),
           let value = root["value"] as? [String: Any],
           let errName = value["error"] as? String,
           webDriverW3CValueErrorIndicatesDeadSession(errName) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw HeadlessChromiumError.webDriverError(status: 404, body: text)
        }
        return data
    }
    
    private static func webDriverDELETE(baseURL: String, path: String, timeoutSeconds: Int64) async throws {
        let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        var request = HTTPClientRequest(url: urlString)
        request.method = .DELETE
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(timeoutSeconds))
        var discard = try await response.body.collect(upTo: 65536)
        _ = discard.readData(length: discard.readableBytes)
        guard (200..<300).contains(response.status.code) else {
            throw HeadlessChromiumError.webDriverError(status: Int(response.status.code), body: "")
        }
    }
    
    private static func parseJSONObject(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw HeadlessChromiumError.webDriverDecodeFailed(body: String(data: data, encoding: .utf8) ?? "")
        }
        return dict
    }
    
    private static func extractSessionId(from responseData: Data) throws -> String {
        let root = try parseJSONObject(responseData)
        guard let value = root["value"] as? [String: Any],
              let sid = value["sessionId"] as? String else {
            throw HeadlessChromiumError.webDriverDecodeFailed(body: String(data: responseData, encoding: .utf8) ?? "")
        }
        return sid
    }
    
    private static func extractPrintPDFBase64(from responseData: Data) throws -> String {
        let root = try parseJSONObject(responseData)
        guard let value = root["value"] as? [String: Any],
              let b64 = value["data"] as? String else {
            throw HeadlessChromiumError.webDriverDecodeFailed(body: String(data: responseData, encoding: .utf8) ?? "")
        }
        return b64
    }
    
    private static func buildNewSessionBody(chromeBinary: URL, dockerSafe: Bool) throws -> Data {
        var chromeArgs = [
            "--headless=new",
            "--disable-gpu",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-dev-shm-usage",
            "--hide-scrollbars",
            "--mute-audio",
        ]
        if dockerSafe {
            chromeArgs.append(contentsOf: ["--no-sandbox", "--disable-setuid-sandbox"])
        }
        let chromeOpts: [String: Any] = [
            "binary": chromeBinary.path,
            "args": chromeArgs,
        ]
        let caps: [String: Any] = [
            "alwaysMatch": [
                "browserName": "chrome",
                "goog:chromeOptions": chromeOpts,
            ],
        ]
        let payload: [String: Any] = ["capabilities": caps]
        return try JSONSerialization.data(withJSONObject: payload)
    }
    
    private static func navigate(baseURL: String, sessionId: String, url: URL, timeoutSeconds: Int64) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString])
        _ = try await webDriverPOST(
            baseURL: baseURL,
            path: "/session/\(sessionId)/url",
            body: body,
            timeoutSeconds: timeoutSeconds
        )
    }
    
    private static func waitDocumentComplete(baseURL: String, sessionId: String, timeoutSeconds: Int64) async throws {
        let script = "return document.readyState"
        let body = try JSONSerialization.data(withJSONObject: ["script": script, "args": []])
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let data = try await webDriverPOST(
                baseURL: baseURL,
                path: "/session/\(sessionId)/execute/sync",
                body: body,
                timeoutSeconds: min(timeoutSeconds, 30)
            )
            let root = try parseJSONObject(data)
            if let state = root["value"] as? String, state == "complete" {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    
    private static func printCurrentPageToPDFData(baseURL: String, sessionId: String, timeoutSeconds: Int64) async throws -> Data {
        let cdpBody: [String: Any] = [
            "cmd": "Page.printToPDF",
            "params": [
                "printBackground": true,
                "preferCSSPageSize": false,
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: cdpBody)
        let data = try await webDriverPOST(
            baseURL: baseURL,
            path: "/session/\(sessionId)/chromium/send_command_and_get_result",
            body: body,
            timeoutSeconds: timeoutSeconds
        )
        let b64 = try extractPrintPDFBase64(from: data)
        guard let pdf = Data(base64Encoded: b64) else {
            throw HeadlessChromiumError.webDriverDecodeFailed(body: "invalid base64 in printToPDF response")
        }
        return pdf
    }
    
    private static func deleteSession(baseURL: String, sessionId: String, timeoutSeconds: Int64) async {
        try? await webDriverDELETE(baseURL: baseURL, path: "/session/\(sessionId)", timeoutSeconds: timeoutSeconds)
    }
    
    // MARK: - Одноразовые обёртки (локальный chromedriver + одна сессия на вызов)
    
    /// Удобство для тестов: одна сессия, один URL → файл (chromedriver по умолчанию **не** стартуем локально).
    public static func printURLToPDF(
        url: URL,
        outputPDF: URL,
        driverBaseURL: String? = nil,
        driverPort: Int = 9515,
        chromedriverExecutable: URL? = nil,
        browserExecutable: URL? = nil,
        manageChromedriverProcess: Bool = false,
        dockerSafe: Bool = false,
        preflightHTTP: Bool = true,
        httpTimeoutSeconds: Int64 = 60,
        pageLoadTimeoutSeconds: Int64 = 60
    ) async throws {
        let base = normalizedDriverBaseURL(explicit: driverBaseURL, driverPort: driverPort)
        var driverProcess: Process?
        if manageChromedriverProcess {
            let driverExec: URL
            if let chromedriverExecutable {
                driverExec = chromedriverExecutable
            } else {
                driverExec = try resolveChromedriverExecutable()
            }
            let proc = Process()
            proc.executableURL = driverExec
            proc.arguments = ["--port=\(driverPort)", "--allowed-origins=*"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            driverProcess = proc
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        defer {
            driverProcess?.terminate()
            driverProcess?.waitUntilExit()
        }
        let session = try await openSession(
            driverBaseURL: manageChromedriverProcess ? "http://127.0.0.1:\(driverPort)" : base,
            driverPort: driverPort,
            browserExecutable: browserExecutable,
            dockerSafe: dockerSafe,
            httpTimeoutSeconds: httpTimeoutSeconds,
            pageLoadTimeoutSeconds: pageLoadTimeoutSeconds
        )
        defer {
            Task { await session.close() }
        }
        try await session.printPage(url: url, to: outputPDF, preflightHTTP: preflightHTTP)
    }
    
    /// Несколько URL подряд в **одной** сессии (без рестарта браузера между ними).
    public static func printURLsToPDFs(
        urls: [URL],
        outputDirectory: URL,
        fileNamePrefix: String = "page",
        driverBaseURL: String? = nil,
        driverPort: Int = 9515,
        chromedriverExecutable: URL? = nil,
        browserExecutable: URL? = nil,
        manageChromedriverProcess: Bool = false,
        dockerSafe: Bool = false,
        preflightHTTP: Bool = true,
        httpTimeoutSeconds: Int64 = 60,
        pageLoadTimeoutSeconds: Int64 = 60
    ) async throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: outputDirectory.path),
              fm.isWritableFile(atPath: outputDirectory.path) else {
            throw HeadlessChromiumError.outputDirectoryNotWritable(outputDirectory)
        }
        let base = normalizedDriverBaseURL(explicit: driverBaseURL, driverPort: driverPort)
        var driverProcess: Process?
        if manageChromedriverProcess {
            let driverExec: URL
            if let chromedriverExecutable {
                driverExec = chromedriverExecutable
            } else {
                driverExec = try resolveChromedriverExecutable()
            }
            let proc = Process()
            proc.executableURL = driverExec
            proc.arguments = ["--port=\(driverPort)", "--allowed-origins=*"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            driverProcess = proc
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        defer {
            driverProcess?.terminate()
            driverProcess?.waitUntilExit()
        }
        let connectURL = manageChromedriverProcess ? "http://127.0.0.1:\(driverPort)" : base
        let session = try await openSession(
            driverBaseURL: connectURL,
            driverPort: driverPort,
            browserExecutable: browserExecutable,
            dockerSafe: dockerSafe,
            httpTimeoutSeconds: httpTimeoutSeconds,
            pageLoadTimeoutSeconds: pageLoadTimeoutSeconds
        )
        defer {
            Task { await session.close() }
        }
        var outputs: [URL] = []
        for (index, url) in urls.enumerated() {
            let out = outputDirectory.appendingPathComponent("\(fileNamePrefix)-\(index).pdf")
            try await session.printPage(url: url, to: out, preflightHTTP: preflightHTTP)
            outputs.append(out)
        }
        return outputs
    }
}
