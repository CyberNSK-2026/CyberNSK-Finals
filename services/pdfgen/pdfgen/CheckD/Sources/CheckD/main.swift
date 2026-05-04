import AsyncHTTPClient
import Foundation
import PostgresNIO
import FastCGI2
import Atomics
import ServiceStdio

await ServiceStdio.shared.bootstrap()
await ServiceStdio.shared.log("CheckD: stderr via ServiceStdio.log (serialized write)")

let group = MultiThreadedEventLoopGroup(numberOfThreads: max(System.coreCount, 2))
let server = FastCGIServer(group: group)

private let psqlHost: String = {
    let raw = ProcessInfo.processInfo.environment["PG_HOST"] ?? ""
    return raw.isEmpty ? "127.0.0.1" : raw
}()

private let psqlPort: Int = {
    let raw = ProcessInfo.processInfo.environment["PG_PORT"] ?? ""
    if raw.isEmpty { return 5006 }
    return Int(raw) ?? 5006
}()

/// ENV: **`PG_USER`**, иначе **`checkd`**.
private let psqlUser: String = {
    let raw = ProcessInfo.processInfo.environment["PG_USER"] ?? ""
    return raw.isEmpty ? "checkd" : raw
}()

/// ENV: **`PG_PASSWORD`**, иначе **`ctf_pass`**.
private let psqlPassword: String = {
    let raw = ProcessInfo.processInfo.environment["PG_PASSWORD"] ?? ""
    return raw.isEmpty ? "ctf_pass" : raw
}()

/// ENV: **`PG_DATABASE`**, иначе **`checkd`**.
private let psqlDatabase: String = {
    let raw = ProcessInfo.processInfo.environment["PG_DATABASE"] ?? ""
    return raw.isEmpty ? "checkd" : raw
}()

let psql_params: PostgresClient.Configuration = PostgresClient.Configuration(
    host: psqlHost,
    port: psqlPort,
    username: psqlUser,
    password: psqlPassword,
    database: psqlDatabase,
    tls: .disable
)
let database = PostgresClient(configuration: psql_params)
await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        await InitAuthRoures();
        await InitListsRoutes();
        await InitExportRoutes();
        await InitFileRoutes();
        await InitUserRoutes();
        await InitPrintRoutes();
        try await server.serveForever(host: "127.0.0.1", port: 5005)
    }
    group.addTask {
        await database.run()
    }
}
