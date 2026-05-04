
import Foundation
import NIOCore

enum FastCGITypes: UInt8 {
    case BEGIN_REQUEST = 1
    case ABORT_REQUEST = 2
    case END_REQUEST = 3
    case PARAMS = 4
    case STDIN = 5
    case STDOUT = 6
    case STDERR = 7
    case DATA = 8
    case GET_VALUES = 9
    case GET_VALUES_RESULT = 10
    case UNKNOWN_TYPE = 11

    public static func fromUInt8(from: UInt8) -> FastCGITypes {
        guard let v = FastCGITypes.init(rawValue: from) else {
            return FastCGITypes.UNKNOWN_TYPE;
        }
        return v;
    }
}

struct FCGI_Header: ByteBufferDecodable, ByteBufferEncodable {
    public var version: UInt8;
    public var type: FastCGITypes;
    public var requestId: UInt16;
    public var contentLength: UInt16;
    public var paddingLength: UInt8;
    
    init(from: inout NIOCore.ByteBuffer) throws {
        self.version = try from.readInteger(endianness: .big, as: UInt8.self) ?? {throw ModelError.InvaludBuffer("FastCGIHeader.version")}()
        self.type = try .fromUInt8(from: from.readInteger(endianness: .big, as: UInt8.self) ?? {throw ModelError.InvaludBuffer("FastCGIHeader.type")}())
        self.requestId = try from.readInteger(endianness: .big, as: UInt16.self) ?? {throw ModelError.InvaludBuffer("FastCGIHeader.requestId")}()
        self.contentLength = try from.readInteger(endianness: .big, as: UInt16.self) ?? {throw ModelError.InvaludBuffer("FastCGIHeader.contentLength")}()
        self.paddingLength = try from.readInteger(endianness: .big, as: UInt8.self) ?? {throw ModelError.InvaludBuffer("FastCGIHeader.paddingLength")}()
        guard from.readableBytes >= 1 else {
            throw ModelError.InvaludBuffer("FastCGIHeader.reserved")
        } 
        from.moveReaderIndex(forwardBy: 1)
    }

    init(version: UInt8, type: FastCGITypes, requestId: UInt16, contentLength: UInt16, paddingLength: UInt8) {
        self.version = version
        self.type = type
        self.requestId = requestId
        self.contentLength = contentLength
        self.paddingLength = paddingLength
    }

    func encode(to: inout NIOCore.ByteBuffer) {
        to.writeInteger(self.version, endianness: .big)
        to.writeInteger(self.type.rawValue, endianness: .big)
        to.writeInteger(self.requestId, endianness: .big)
        to.writeInteger(self.contentLength, endianness: .big)
        to.writeInteger(self.paddingLength, endianness: .big)
        to.writeRepeatingByte(0, count: 1)
    }
}

enum FastCGIRole: UInt8 {
    case RESPONDER = 1
    case AUTHORIZER = 2
    case FILTER = 3
    case UNKNOWN = 255

    public static func fromUInt8(from: UInt8) -> FastCGIRole {
        guard let v = FastCGIRole.init(rawValue: from) else {
            return FastCGIRole.UNKNOWN;
        }
        return v;
    }
}

struct FCGI_BeginRequestBody: ByteBufferDecodable {
    public var role: UInt16;
    public var flags: UInt8;

    init(from: inout NIOCore.ByteBuffer) throws {
        self.role = try from.readInteger(endianness: .big, as: UInt16.self) ?? {throw ModelError.InvaludBuffer("FCGI_BeginRequestBody.role")}()
        self.flags = try from.readInteger(endianness: .big, as: UInt8.self) ?? {throw ModelError.InvaludBuffer("FCGI_BeginRequestBody.flags")}()
        guard from.readableBytes >= 5 else {
            throw ModelError.InvaludBuffer("FCGI_BeginRequestBody.reserved")
        } 
        from.moveReaderIndex(forwardBy: 5)
    }
}

enum FastCGIProtocolStatus: UInt8 {
    case REQUEST_COMPLETE = 0
    case CANT_MPX_CONN = 1
    case OVERLOADED = 2
    case UNKNOWN_ROLE = 3
}

struct FCGI_EndRequestBody: ByteBufferEncodable {
    public var appStatus: UInt32;
    public var protocolStatus: FastCGIProtocolStatus;

    func encode(to: inout NIOCore.ByteBuffer) {
        to.writeInteger(self.appStatus, endianness: .big)
        to.writeInteger(self.protocolStatus.rawValue, endianness: .big)
        to.writeRepeatingByte(0, count: 3)
    }
}

struct FCGI_KVPair: ByteBufferDecodable, ByteBufferEncodable{
    public var key: String
    public var value: String

    init(from: inout NIOCore.ByteBuffer) throws {
        var keyLen: UInt32
        var valLen: UInt32

        keyLen = try UInt32(from.readInteger(endianness: .big, as: UInt8.self) ?? {throw ModelError.InvaludBuffer("FCGI_KVPair.keyLen")}())
        if (keyLen & 0x80) != 0 {
            from.moveReaderIndex(to: from.readerIndex - 1)
            keyLen = try from.readInteger(endianness: .big, as: UInt32.self) ?? {throw ModelError.InvaludBuffer("FCGI_KVPair.keyLen")}()
            keyLen &= 0x7FFFFFFF
        }

        valLen = try UInt32(from.readInteger(endianness: .big, as: UInt8.self) ?? {throw ModelError.InvaludBuffer("FCGI_KVPair.valLen")}())
        if (valLen & 0x80) != 0 {
            from.moveReaderIndex(to: from.readerIndex - 1)
            valLen = try from.readInteger(endianness: .big, as: UInt32.self) ?? {throw ModelError.InvaludBuffer("FCGI_KVPair.valLen")}()
            valLen &= 0x7FFFFFFF
        }

        self.key = try from.readString(length: Int(keyLen)) ?? {throw ModelError.InvaludBuffer("FCGI_KVPair.Key")}()
        self.value = try from.readString(length: Int(valLen)) ?? {throw ModelError.InvaludBuffer("FCGI_KVPair.Value")}()
    }

    func encode(to: inout NIOCore.ByteBuffer) {
        var keyLen = UInt32(self.key.lengthOfBytes(using: .utf8))
        var valLen = UInt32(self.key.lengthOfBytes(using: .utf8))
        if keyLen > 127 {
            keyLen |= (1 << 31);
            to.writeInteger(keyLen, endianness: .big)
        } else {
            to.writeInteger(UInt8(keyLen), endianness: .big)
        }
        if valLen > 127 {
            valLen |= (1 << 31);
            to.writeInteger(valLen, endianness: .big)
        } else {
            to.writeInteger(UInt8(valLen), endianness: .big)
        }
        to.writeString(self.key)
        to.writeString(self.value)
    }
}

enum FCGI_Message {
    case BeginRequest(FCGI_BeginRequestBody)
    case AbortRequest
    case EndRequest(FCGI_EndRequestBody)
    case Params([FCGI_KVPair])
    case STDIN(ByteBuffer)
    case STDOUT(ByteBuffer)
    case STDERR(ByteBuffer)
    case DATA(ByteBuffer)
    case EOF(UInt32, FastCGIProtocolStatus)
    case Unknown
}