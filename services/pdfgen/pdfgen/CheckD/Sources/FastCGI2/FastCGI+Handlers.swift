import NIOCore
import NIOPosix
import Foundation
import Atomics
import Dispatch
import ServiceStdio

public struct Request {
    fileprivate let handler: FastCGIInboundHandler;

    public var readableBytes: Int {
        get {
            return self.handler.getReadableBytes()
        }
    }

    public func readBytes(buffer: inout ByteBuffer, limit: Int) async -> Int {
        await self.handler.readBytes(buffer: &buffer, limit: limit)
    }

    public func writeBytes(buffer: inout ByteBuffer) async throws -> Int {
        try await self.handler.writeBytes(buffer: &buffer)
    }

    public func writeResponseHead(statusCode: Int, contentType: String, headers: [String:String]?) async throws -> Int {
        try await self.handler.writeResponseHead(statusCode: statusCode, contentType: contentType, headers: headers)
    }

    public func writeEOF(statusCode: UInt32) async throws -> Int {
        try await self.handler.writeEOF(statusCode: statusCode)
    }

    public func getParam(param: String) -> String? {
        self.handler.params[param]
    }
}

public struct Response {
    let statusCode: Int
    let contentType: String
    var data: ByteBuffer
    let headers: [String:String]?

    public init(statusCode: Int, contentType: String, data: ByteBuffer, headers: [String:String]?) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.data = data
        self.headers = headers
    }

    public init(statusCode: Int, contentType: String, data: ByteBuffer) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.data = data
        self.headers = nil
    }
}


enum Data_StateMachine {
    case Idle
    case ReadingHeader(Int)
    case ReadingBody(Int)
}

final class FastCGIBytesToMessageHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = FCGI_Message

    private var stateMachine: Data_StateMachine = .Idle
    private var cumulationBuffer: ByteBuffer = ByteBuffer()
    private var header: FCGI_Header? = nil

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bb = self.unwrapInboundIn(data);
        //print("FastCGIBytesToMessageHandler Channel got data!", bb.readableBytes)
        self.doRead(context: context, data: &bb)        
    }

    private func doRead(context: ChannelHandlerContext, data: inout ByteBuffer) {
        switch (self.stateMachine) {
            case .Idle:
                if data.readableBytes < 8 {
                    self.cumulationBuffer.clear()
                    self.cumulationBuffer.writeBuffer(&data)
                    self.stateMachine = .ReadingHeader(8 - self.cumulationBuffer.readableBytes)
                } else {
                    guard let hdr = try? FCGI_Header(from: &data) else {
                        //Must not be
                        return
                    }
                    self.header = hdr
                    if data.readableBytes >= Int(self.header!.contentLength + UInt16(self.header!.paddingLength)) {
                        let msg = self.readFCGIBody(header: self.header!, data: &data, allocator: context.channel.allocator)
                        self.stateMachine = .Idle
                        context.fireChannelRead(self.wrapInboundOut(msg))
                        if data.readableBytes > 0 {
                            self.doRead(context: context, data: &data)
                        }
                    } else {
                        self.cumulationBuffer.clear()
                        self.cumulationBuffer.writeBuffer(&data)
                        self.stateMachine = .ReadingBody(Int(self.header!.contentLength + UInt16(self.header!.paddingLength)) - self.cumulationBuffer.readableBytes)
                    }
                }
            break
            case .ReadingHeader(let remain):
                if (data.readableBytes) < remain {
                    self.cumulationBuffer.writeBuffer(&data)
                    self.stateMachine = .ReadingHeader(8 - self.cumulationBuffer.readableBytes)
                } else {
                    self.cumulationBuffer.writeImmutableBuffer(data.readSlice(length: remain)!)
                    guard let hdr = try? FCGI_Header(from: &self.cumulationBuffer) else {
                        //Must not be
                        return
                    }
                    self.header = hdr
                    if data.readableBytes >= Int(self.header!.contentLength + UInt16(self.header!.paddingLength)) {
                        let msg = self.readFCGIBody(header: self.header!, data: &data, allocator: context.channel.allocator)
                        self.stateMachine = .Idle
                        context.fireChannelRead(self.wrapInboundOut(msg))
                        if data.readableBytes > 0 {
                            self.doRead(context: context, data: &data)
                        }
                    } else {
                        self.cumulationBuffer.clear()
                        self.cumulationBuffer.writeBuffer(&data)
                        self.stateMachine = .ReadingBody(Int(self.header!.contentLength + UInt16(self.header!.paddingLength)) - self.cumulationBuffer.readableBytes)
                    }
                }
            break
            case .ReadingBody(let remain):
                if (data.readableBytes) < remain {
                    self.cumulationBuffer.writeBuffer(&data)
                    self.stateMachine = .ReadingBody(Int(self.header!.contentLength + UInt16(self.header!.paddingLength)) - self.cumulationBuffer.readableBytes)
                } else {
                    self.cumulationBuffer.writeImmutableBuffer(data.readSlice(length: remain)!)
                    let msg = self.readFCGIBody(header: self.header!, data: &self.cumulationBuffer, allocator: context.channel.allocator)
                    self.stateMachine = .Idle
                    context.fireChannelRead(self.wrapInboundOut(msg))
                    if data.readableBytes > 0 {
                        self.doRead(context: context, data: &data)
                    }
                }
            break

        }
    }

    private func readFCGIBody(header: FCGI_Header, data: inout ByteBuffer, allocator: ByteBufferAllocator) -> FCGI_Message {
        switch(header.type) {
            case .BEGIN_REQUEST: 
                guard let body = try? FCGI_BeginRequestBody(from: &data) else {
                    return .Unknown
                }
                if header.paddingLength > 0 {
                    data.moveReaderIndex(forwardBy: Int(header.paddingLength))
                }
                return .BeginRequest(body)
            case .ABORT_REQUEST:
                return .AbortRequest
            case .PARAMS:
                var kv_store: [FCGI_KVPair] = []
                let tot = data.readableBytes
                while((tot - data.readableBytes) < header.contentLength) {
                    guard let kv = try? FCGI_KVPair(from: &data) else {
                        return .Unknown
                    }
                    kv_store.append(kv)
                }
                if header.paddingLength > 0 {
                    data.moveReaderIndex(forwardBy: Int(header.paddingLength))
                }
                return .Params(kv_store)
            case .STDIN:
                let bb = allocator.buffer(buffer: data.readSlice(length: Int(header.contentLength))!)
                if header.paddingLength > 0 {
                    data.moveReaderIndex(forwardBy: Int(header.paddingLength))
                }
                return .STDIN(bb)
            case .DATA:
                let bb = allocator.buffer(buffer: data.readSlice(length: Int(header.contentLength))!)
                if header.paddingLength > 0 {
                    data.moveReaderIndex(forwardBy: Int(header.paddingLength))
                }
                return .DATA(bb)
            default:
                return .Unknown
        }
    }
}

enum FCGI_StateMachine {
    case New
    case ReadingParams
    case ReadingBody
    case BodyCompleted
    case Finished
}

final class FastCGIInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias OutboundIn = ByteBuffer
    typealias InboundIn = FCGI_Message

    private var stateMachine: FCGI_StateMachine = .New

    private var cumulatinBuffer: ByteBuffer = ByteBuffer()

    fileprivate var params: [String: String] = [:];
    private var body: ByteBuffer = ByteBuffer()
    private var continuation: UnsafeContinuation<Int,Never>?;

    let semaphore = DispatchSemaphore(value: 1)
    var channel: (any Channel)? = nil
    var task: Task<Void,Never>? = nil

    let pathResolver: PathResolver

    public init(resolver: PathResolver) {
        self.pathResolver = resolver
    }

    public func channelRegistered(context: ChannelHandlerContext) {
        self.channel = context.channel
    }

    public func channelUnregistered(context: ChannelHandlerContext) {
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
            case .BeginRequest(let bg):
            //print(bg)
            self.stateMachine = .ReadingParams
            break
            case .Params(let params):
            if params.count > 0 {
                for kv in params {
                    self.params[kv.key] = kv.value
                }
            } else {
                self.stateMachine = .ReadingBody
            }
            break
            case .STDIN(let x):
            
            if(x.readableBytes > 0) {
                semaphore.wait()
                self.cumulatinBuffer.writeImmutableBuffer(x)
                if self.continuation != nil  {
                    self.continuation!.resume(returning: self.cumulatinBuffer.readableBytes)
                    self.continuation = nil
                }
                semaphore.signal()
            } else {
                if self.continuation != nil  {
                    self.continuation!.resume(returning: 0)
                }
                
                if self.task == nil {
                    self.task = Task {
                        let req = Request(handler: self)
                        let timeStart = Date.now
                        var resp = await self.pathResolver.Invoke(name: String(self.params["path"]!.split(separator: "?")[0]), method: self.params["method"]!, req: req)
                        let timeEnd = Date.now
                        let line = "[\(timeEnd.ISO8601Format())] http: \(req.getParam(param: "method")!.uppercased()) \(req.getParam(param: "path")!) (\((timeStart.distance(to: timeEnd) * 1000).rounded()) ms) \(resp.statusCode)"
                        await ServiceStdio.shared.log(line)
                        try? await self.writeResponseHead(statusCode: resp.statusCode, contentType: resp.contentType, headers: resp.headers)
                        try? await self.writeBytes(buffer: &resp.data)
                        try? await self.writeEOF(statusCode: 0)
                    }
                }
                
                self.stateMachine = .BodyCompleted
            }
            break
            default:
            break 
        }   
    }

    public func readBytes(buffer: inout ByteBuffer, limit: Int) async -> Int {
        await withUnsafeContinuation { cont in
            semaphore.wait()
            cont.resume(returning: Void())
        }
        
        var unlocked = false
        defer {
            if !unlocked {
                semaphore.signal()
            }
        }
        if self.cumulatinBuffer.readableBytes == 0 {
            let r = await withUnsafeContinuation { cont in
                self.continuation = cont
                semaphore.signal()
                unlocked = true
            }
            if r > 0 {
                return buffer.writeImmutableBuffer(self.cumulatinBuffer.readSlice(length: min(self.cumulatinBuffer.readableBytes, limit))!);
            } else {
                return 0
            }
        } else {
            return buffer.writeImmutableBuffer(self.cumulatinBuffer.readSlice(length: min(self.cumulatinBuffer.readableBytes, limit))!);
        }
    }

    public func getReadableBytes() -> Int {
        return self.cumulatinBuffer.readableBytes;
    }

    public func writeBytes(buffer: inout ByteBuffer) async throws -> Int {
        try await withUnsafeThrowingContinuation { cont in
            let len = buffer.readableBytes
            let future = channel!.write(FCGI_Message.STDOUT(buffer));
            future.whenSuccess { Void in
                cont.resume(returning: len)
            }
            future.whenFailure { error in
                cont.resume(throwing: error)
            }
        }
    }

    public func writeResponseHead(statusCode: Int, contentType: String, headers: [String:String]?) async throws -> Int {
        var outBuffer = self.channel!.allocator.buffer(string: "Status: \(statusCode)\r\nContent-Type: \(contentType)\r\n")
        if headers != nil {
            for (k, v) in headers! {
                outBuffer.writeString("\(k): \(v)\r\n")
            }
        }
        outBuffer.writeString("\r\n")
        return try await self.writeBytes(buffer: &outBuffer)
    }

    public func writeEOF(statusCode: UInt32) async throws -> Int {
        try await withUnsafeThrowingContinuation { cont in
            let future = channel!.write(FCGI_Message.EOF(statusCode, .REQUEST_COMPLETE));
            future.whenSuccess { Void in
                cont.resume(returning: 0)
                self.channel!.close()
            }
            future.whenFailure { error in
                cont.resume(throwing: error)
            }
        }
    }
}

enum OutboundErrors: Error {
    case InvalidType(String)
}

final class FastCGIOutboundHandler: ChannelOutboundHandler {
    typealias OutboundIn = FCGI_Message
    typealias OutboundOut = ByteBuffer

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let fcgi_data = self.unwrapOutboundIn(data)
        //print(fcgi_data)

        switch (fcgi_data) {
            case .STDOUT(var output_data):
                while(output_data.readableBytes > 0) {
                    let ln = UInt16(min(output_data.readableBytes, 65535))
                    let header = FCGI_Header(version: 1, type: FastCGITypes.STDOUT, requestId: 1, contentLength: ln, paddingLength: 0)
                    let slice = output_data.readSlice(length: Int(ln))!
                    var outBB = context.channel.allocator.buffer(capacity: 8 + Int(ln));
                    header.encode(to: &outBB);
                    outBB.writeImmutableBuffer(slice)
                    context.write(self.wrapOutboundOut(outBB))
                }
                promise?.succeed()
                break
            case .EOF(let appState, let procState):
                var outBB = context.channel.allocator.buffer(capacity: Int(8));
                FCGI_Header(version: 1, type: FastCGITypes.STDOUT, requestId: 1, contentLength: 0, paddingLength: 0).encode(to: &outBB)
                context.write(self.wrapOutboundOut(outBB), promise: promise)
                outBB.clear()
                FCGI_Header(version: 1, type: FastCGITypes.END_REQUEST, requestId: 1, contentLength: 8, paddingLength: 0).encode(to: &outBB)
                context.write(self.wrapOutboundOut(outBB));
                outBB.clear()
                FCGI_EndRequestBody(appStatus: appState, protocolStatus: procState).encode(to: &outBB)
                context.writeAndFlush(self.wrapOutboundOut(outBB), promise: promise)
                break
            default:
                promise?.fail(OutboundErrors.InvalidType("Invalid"))
                break
        }
    }
}
