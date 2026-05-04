import FastCGI2
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOPosix
import ServiceStdio

fileprivate func jsonResponseBody(_ encoder: JSONEncoder, _ value: some Encodable) throws -> ByteBuffer {
    let data = try encoder.encode(value)
    return ByteBuffer(bytes: [UInt8](data))
}

await ServiceStdio.shared.bootstrap()
await ServiceStdio.shared.log("CheckDPrintService: stderr via ServiceStdio.log (serialized write); libc stdio unbuffered after bootstrap")

let group = MultiThreadedEventLoopGroup(numberOfThreads: max(System.coreCount, 2))
let server = FastCGIServer(group: group)

let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes]

/// Хост (и порт) для `pdfurl`, как клиенты должны ходить к nginx `/files/…`.
let printPublicHostname: String = {
    let raw = ProcessInfo.processInfo.environment["PRINT_PUBLIC_HOSTNAME"] ?? ""
    return raw.isEmpty ? "print-service" : raw
}()
let printPublicPort: Int = {
    guard let s = ProcessInfo.processInfo.environment["PRINT_PUBLIC_PORT"], !s.isEmpty,
          let p = Int(s), p > 0, p <= 65535
    else { return 8080 }
    return p
}()

await server.on(path: "/print-service/print-page", method: "POST") { req in
    do {
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            return Response(statusCode: 400, contentType: "application/json", data: try! jsonResponseBody(encoder, PrintPageResponse(
                ok: false,
                pdfurl: nil,
                error: "Body is too large"
            )))
        }
        
        let reqData: PrintPageRequest
        do {
            reqData = try JSONDecoder().decode(PrintPageRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 500, contentType: "application/json", data: try! jsonResponseBody(encoder, PrintPageResponse(
                ok: false,
                pdfurl: nil,
                error: "bad request"
            )))
        }
        
        try await chromeDriver.startSession()
        try await chromeDriver.navigate(url: reqData.url)
        await ServiceStdio.shared.log("Navigated to \(reqData.url.absoluteString)")
        let b64 = try await chromeDriver.printCurrentPageB64()
        let pdfData = Data(base64Encoded: b64)!
        await ServiceStdio.shared.log("Printed: \(pdfData.count) bytes")
        let file = await fileStore.create(ttl: reqData.fileTTL)
        guard FileManager.default.createFile(atPath: file.path, contents: pdfData) else {
            await ServiceStdio.shared.log("File is not saved")
            return Response(statusCode: 500, contentType: "application/json", data: try! jsonResponseBody(encoder, PrintPageResponse(
                ok: false,
                pdfurl: nil,
                error: "Saving file failed"
            )))
        }
        await ServiceStdio.shared.log("Saved file!")
        try await chromeDriver.closePage()
        
        return Response(statusCode: 200, contentType: "application/json", data: try! jsonResponseBody(encoder, PrintPageResponse(
            ok: true,
            pdfurl: "\(file.lastPathComponent)",
            error: nil
        )))
    } catch {
        await ServiceStdio.shared.log("Got an error while printing: \(error), restarting chrome session")
        try? await chromeDriver.restartSession()
        return Response(statusCode: 500, contentType: "application/json", data: try! jsonResponseBody(encoder, PrintPageResponse(
            ok: false,
            pdfurl: nil,
            error: "got an error: \(error)"
        )))
    }
}

let basePath = ProcessInfo.processInfo.environment["FILESTORE_PATH"] ?? "/Volumes/Work/CTF/filestore";

let chromeDriver = ChromedriverManager()
let fileStore = try FileTTLStore(basePath: URL(filePath: basePath), defaultTTL: 60)

await ServiceStdio.shared.log("Server started (FastCGI 127.0.0.1:5004)")


await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        try await server.serveForever(host: "127.0.0.1", port: 5004)
    }
    group.addTask {
        do {
            try await chromeDriver.runForever()
        } catch {
            await ServiceStdio.shared.log("Chrome serve failed: \(error)")
        }
    }
    group.addTask {
        do {
            try? await Task.sleep(for: .seconds(5))
            await ServiceStdio.shared.log("Starting chrome")
            try await chromeDriver.startSession()
            await ServiceStdio.shared.log("Chrome started")
        } catch {
            await ServiceStdio.shared.log("Got an exception while starting chrome: \(error)")
        }
    }
    group.addTask {
        while true {
            await fileStore.cleanup()
            try? await Task.sleep(for: .seconds(10))
        }
    }
    group.addTask {
        while true {
            try? await Task.sleep(for: .seconds(5*60))
            await ServiceStdio.shared.log("Restarting chrome!")
            try? await chromeDriver.restartSession()
        }
    }
}
