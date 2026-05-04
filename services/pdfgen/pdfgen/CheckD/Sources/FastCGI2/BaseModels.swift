import NIOCore

protocol ByteBufferEncodable {
    func encode(to: inout ByteBuffer);
}

protocol ByteBufferDecodable {
    init(from: inout ByteBuffer) throws;
}

enum ModelError: Error {
    case InvaludBuffer(String)
}
