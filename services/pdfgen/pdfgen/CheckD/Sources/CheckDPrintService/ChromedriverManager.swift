import AsyncHTTPClient
import Foundation
import NIOCore

enum ChromedriverManagerError: Error {
    case chromedriverNotFound(path: String)
    case chromeBinaryNotFound(searched: [String])
    case processNotRunning
    case sessionMissing
    case invalidResponse(String)
}

actor ChromedriverManager {
    private let driverPort: Int
    private let driverBaseURL: String
    private let httpTimeoutSeconds: Int64

    private var driverProcess: Process?
    private var shouldStopDriver: Bool = false
    private var sessionId: String?

    private var busy: Bool = false
    private var busyQueue: [CheckedContinuation<Void, Never>] = []

    init(driverPort: Int = 9515, httpTimeoutSeconds: Int64 = 60) {
        self.driverPort = driverPort
        self.driverBaseURL = "http://127.0.0.1:\(driverPort)"
        self.httpTimeoutSeconds = httpTimeoutSeconds
    }

    // MARK: - Async lock

    private func enshureFree() async {
        if !self.busy {
            return
        }
        await withCheckedContinuation { cont in
            self.busyQueue.append(cont)
        }
    }

    private func setBusy(busy: Bool) {
        self.busy = busy
        if !busy {
            if !self.busyQueue.isEmpty {
                self.busyQueue.removeFirst().resume()
            }
        }
    }

    private func lock() async {
        await self.enshureFree()
        self.setBusy(busy: true)
    }

    private func unlock() {
        self.setBusy(busy: false)
    }

    // MARK: - Driver lifecycle

    func runForever() async throws {
        shouldStopDriver = false
        while !shouldStopDriver {
            if driverProcess == nil || driverProcess?.isRunning == false {
                let process = try makeDriverProcess()
                try process.run()
                driverProcess = process
            }

            while !shouldStopDriver, let proc = driverProcess, proc.isRunning {
                try await Task.sleep(nanoseconds: 500_000_000)
            }

            if let proc = driverProcess, !proc.isRunning {
                driverProcess = nil
                sessionId = nil
            }
        }

        if let proc = driverProcess, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        driverProcess = nil
        sessionId = nil
    }

    func stopDriver() async {
        shouldStopDriver = true
        if let proc = driverProcess, proc.isRunning {
            proc.terminate()
        }
    }

    // MARK: - Session lifecycle

    func startSession() async throws {
        await lock()
        defer { unlock() }

        if sessionId != nil {
            return
        }

        guard driverProcess?.isRunning == true else {
            throw ChromedriverManagerError.processNotRunning
        }

        let body = try newSessionRequestBody()
        let response = try await post(path: "/session", body: body)
        let root = try parseJSON(response)
        guard
            let value = root["value"] as? [String: Any],
            let sid = value["sessionId"] as? String
        else {
            throw ChromedriverManagerError.invalidResponse(String(data: response, encoding: .utf8) ?? "")
        }
        sessionId = sid
    }

    func stopSession() async throws {
        await lock()
        defer { unlock() }

        guard let sid = sessionId else {
            return
        }
        try await delete(path: "/session/\(sid)")
        sessionId = nil
    }

    func restartSession() async throws {
        await lock()
        defer { unlock() }

        if let sid = sessionId {
            try? await delete(path: "/session/\(sid)")
            sessionId = nil
        }

        let body = try newSessionRequestBody()
        let response = try await post(path: "/session", body: body)
        let root = try parseJSON(response)
        guard
            let value = root["value"] as? [String: Any],
            let sid = value["sessionId"] as? String
        else {
            throw ChromedriverManagerError.invalidResponse(String(data: response, encoding: .utf8) ?? "")
        }
        sessionId = sid
    }

    // MARK: - Browser actions

    func navigate(url: URL) async throws {
        await lock()
        defer { unlock() }

        guard let sid = sessionId else {
            throw ChromedriverManagerError.sessionMissing
        }
        let body = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString])
        _ = try await post(path: "/session/\(sid)/url", body: body)
    }

    func printCurrentPageB64() async throws -> String {
        await lock()
        defer { unlock() }

        guard let sid = sessionId else {
            throw ChromedriverManagerError.sessionMissing
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "cmd": "Page.printToPDF",
            "params": [
                "printBackground": true,
            ],
        ])
        let response = try await post(path: "/session/\(sid)/chromium/send_command_and_get_result", body: body)
        let root = try parseJSON(response)
        guard
            let value = root["value"] as? [String: Any],
            let b64 = value["data"] as? String
        else {
            throw ChromedriverManagerError.invalidResponse(String(data: response, encoding: .utf8) ?? "")
        }
        return b64
    }
    
    func closePage() async throws {
        await lock()
        defer { unlock() }
        
        guard let sid = sessionId else {
            throw ChromedriverManagerError.sessionMissing
        }
        
        let currentHandleResponse = try await get(path: "/session/\(sid)/window")
        let currentHandleRoot = try parseJSON(currentHandleResponse)
        guard let oldHandle = currentHandleRoot["value"] as? String, !oldHandle.isEmpty else {
            throw ChromedriverManagerError.invalidResponse(String(data: currentHandleResponse, encoding: .utf8) ?? "")
        }
        
        let createNewTabBody = try JSONSerialization.data(withJSONObject: ["type": "tab"])
        let newTabResponse = try await post(path: "/session/\(sid)/window/new", body: createNewTabBody)
        let newTabRoot = try parseJSON(newTabResponse)
        guard
            let newTabValue = newTabRoot["value"] as? [String: Any],
            let newHandle = newTabValue["handle"] as? String,
            !newHandle.isEmpty
        else {
            throw ChromedriverManagerError.invalidResponse(String(data: newTabResponse, encoding: .utf8) ?? "")
        }
        
        let switchToNewBody = try JSONSerialization.data(withJSONObject: ["handle": newHandle])
        _ = try await post(path: "/session/\(sid)/window", body: switchToNewBody)
        let blankNavigateBody = try JSONSerialization.data(withJSONObject: ["url": "about:blank"])
        _ = try await post(path: "/session/\(sid)/url", body: blankNavigateBody)
        
        let switchToOldBody = try JSONSerialization.data(withJSONObject: ["handle": oldHandle])
        _ = try await post(path: "/session/\(sid)/window", body: switchToOldBody)
        try await delete(path: "/session/\(sid)/window")
        
        // Возвращаем фокус на новую пустую вкладку.
        _ = try await post(path: "/session/\(sid)/window", body: switchToNewBody)
    }

    // MARK: - Chrome / capabilities (headless, без X11)

    private func dockerSafeChromeFlags() -> Bool {
        if let v = ProcessInfo.processInfo.environment["CHROME_DOCKER_SAFE"]?.lowercased() {
            return v == "1" || v == "true" || v == "yes"
        }
        return FileManager.default.fileExists(atPath: "/.dockerenv")
    }

    private func resolveChromeExecutablePath() throws -> String {
        let fm = FileManager.default
        if let raw = ProcessInfo.processInfo.environment["CHROME_PATH"], !raw.isEmpty, fm.isExecutableFile(atPath: raw) {
            return raw
        }
        let candidates = [
            "/opt/chrome-for-testing/chrome-linux64/chrome",
            "/usr/local/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/google-chrome",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        throw ChromedriverManagerError.chromeBinaryNotFound(searched: candidates)
    }

    /// Тело `POST /session`: headless + опции как у CfT в Docker (без дисплея).
    private func newSessionRequestBody() throws -> Data {
        let chromeBin = try resolveChromeExecutablePath()
        var args = [
            "--headless=new",
            "--disable-gpu",
            "--no-first-run",
            "--no-default-browser-check",
            // В Docker /dev/shm по умолчанию 64MB — без этого и без shm_size в compose Chrome часто сразу выходит.
            "--disable-dev-shm-usage",
            "--hide-scrollbars",
            "--mute-audio",
            "--window-size=1280,720",
            "--disable-extensions",
            "--disable-background-networking",
            "--disable-sync",
            "--disable-background-timer-throttling",
            "--disable-backgrounding-occluded-windows",
            "--disable-renderer-backgrounding",
            "--disable-ipc-flooding-protection",
            "--metrics-recording-only",
            "--password-store=basic",
        ]
        if dockerSafeChromeFlags() {
            // Без sandbox в контейнере; --no-zygote часто нужен, иначе дочерний процесс падает при старте.
            args.append(contentsOf: [
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--no-zygote",
            ])
        }
        let chromeOpts: [String: Any] = [
            "binary": chromeBin,
            "args": args,
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

    // MARK: - HTTP helpers
    
    private func dataFromCollectedBuffer(_ buffer: inout ByteBuffer) -> Data {
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            return Data()
        }
        return Data(bytes)
    }

    private func post(path: String, body: Data) async throws -> Data {
        var request = HTTPClientRequest(url: driverBaseURL + path)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(body)

        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(httpTimeoutSeconds))
        var responseBody = try await response.body.collect(upTo: 16 * 1024 * 1024)
        let data = dataFromCollectedBuffer(&responseBody)
        guard (200..<300).contains(response.status.code) else {
            throw ChromedriverManagerError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func delete(path: String) async throws {
        var request = HTTPClientRequest(url: driverBaseURL + path)
        request.method = .DELETE

        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(httpTimeoutSeconds))
        var responseBody = try await response.body.collect(upTo: 1024 * 1024)
        let data = dataFromCollectedBuffer(&responseBody)
        guard (200..<300).contains(response.status.code) else {
            throw ChromedriverManagerError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
    }
    
    private func get(path: String) async throws -> Data {
        var request = HTTPClientRequest(url: driverBaseURL + path)
        request.method = .GET
        
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(httpTimeoutSeconds))
        var responseBody = try await response.body.collect(upTo: 1024 * 1024)
        let data = dataFromCollectedBuffer(&responseBody)
        guard (200..<300).contains(response.status.code) else {
            throw ChromedriverManagerError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChromedriverManagerError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        if let value = dict["value"] as? [String: Any], let err = value["error"] as? String {
            throw ChromedriverManagerError.invalidResponse("webdriver error: \(err)")
        }
        return dict
    }

    private func makeDriverProcess() throws -> Process {
        let executableURL = try resolveChromedriverPath()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--port=\(driverPort)", "--allowed-origins=*"]
        // Наследуем stdout/stderr контейнера — ошибки Chrome/chromedriver видны в `docker logs`.
        return process
    }

    private func resolveChromedriverPath() throws -> URL {
        if let explicit = ProcessInfo.processInfo.environment["CHROMEDRIVER_PATH"], !explicit.isEmpty {
            let url = URL(fileURLWithPath: explicit)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
            throw ChromedriverManagerError.chromedriverNotFound(path: explicit)
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = executable.deletingLastPathComponent().appendingPathComponent("chromedriver")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        throw ChromedriverManagerError.chromedriverNotFound(path: sibling.path)
    }
}
