import NIOCore
import NIOPosix
import Foundation
import Atomics
import Dispatch

public class FastCGIServer: @unchecked Sendable {
    private let bootstrap: ServerBootstrap;
    private let resolver: PathResolver;

    public init(group: EventLoopGroup) {
        self.resolver = PathResolver()
        let resolver = self.resolver
        self.bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(BackPressureHandler())
                    try channel.pipeline.syncOperations.addHandler(FastCGIBytesToMessageHandler())
                    try channel.pipeline.syncOperations.addHandler(FastCGIInboundHandler(resolver: resolver))
                    try channel.pipeline.syncOperations.addHandler(FastCGIOutboundHandler())
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)
            .childChannelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator());
    }

    public func serveForever(host: String, port: UInt16) async throws {
        let channel = try await bootstrap.bind(host: host, port: Int(port)).get()
        try await channel.closeFuture.get()
    }

    public func on(path: String, method: String?, _ handler: @escaping @Sendable (Request) async throws -> (Response)) async {
        await self.resolver.on(name: path, method: method, code: handler)
    }

    public func onSync(path: String, method: String?, _ handler: @escaping @Sendable (Request) async throws -> (Response)) {
        let sem = DispatchSemaphore(value: 0)
        let resolver = self.resolver
        Task {
            await resolver.on(name: path, method: method, code: handler)
            sem.signal()
        }
        sem.wait()
    }
}
