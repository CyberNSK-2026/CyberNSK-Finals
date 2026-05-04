import NIOCore
import NIOPosix
import Foundation
import Atomics
import Dispatch

actor PathResolver {
    public static let HTTP_GET = "GET"
    public static let HTTP_POST = "POST"
    public static let HTTP_PUT = "PUT"
    public static let HTTP_PATCH = "PATCH"

    public static let HTML_405 = "<head><title>Method not allowed</title></head><body><h1>Method not allowed</h1><br>The request method you've send is illegal for this endpoint</body>"
    public static let HTML_404 = "<head><title>Not found</title></head><body><h1>Not found</h1><br>The page you've requested does not exist.</body>"
    public static let HTML_500 = "<head><title>Internal server error</title></head><body><h1>Internal server error</h1><br>An unrecoverable internal server error has been occured.</body>"

    public static let CT_HTML = "text/html"
    public static let CT_JSON = "application/json"

    private var PathStorage : [String:[String: @Sendable (Request) async throws -> (Response)]] = [:];

    public func on(name: String, method: String?, code: @escaping @Sendable (Request) async throws -> (Response)) {
        if(self.PathStorage[name] == nil) {
            self.PathStorage[name] = [:];
        }
        if(method == nil) {
            self.PathStorage[name]!["*"] = code;
        } else {
            self.PathStorage[name]![method!] = code;
        }
        
    }

    nonisolated public func Invoke(name: String, method: String, req: Request) async -> Response {
        var resp: Response?;
        let methodMap = await PathStorage[name];
        var callable: ((Request) async throws -> (Response))? = nil
        if(methodMap != nil) {
            if(methodMap!["*"] != nil) {
                callable = methodMap!["*"]!;
            } else if(methodMap![method] != nil) {
                callable = methodMap![method]!;
            } else {
                var bb = ByteBuffer()
                bb.writeString(PathResolver.HTML_405)
                resp = Response(statusCode: 405, contentType: PathResolver.CT_HTML, data: bb, headers: nil);
            }
        } else {
            var bb = ByteBuffer()
            bb.writeString(PathResolver.HTML_404)
            resp = Response(statusCode: 404, contentType: PathResolver.CT_HTML, data: bb, headers: nil);
        }
        if resp == nil {
            if callable != nil {
                do {
                    resp = try await callable!(req);
                } catch {
                    var bb = ByteBuffer()
                    bb.writeString(PathResolver.HTML_500)
                    resp = Response(statusCode: 500, contentType: PathResolver.CT_HTML, data: bb, headers: nil);
                }
            } else {
                var bb = ByteBuffer()
                bb.writeString(PathResolver.HTML_500)
                resp = Response(statusCode: 500, contentType: PathResolver.CT_HTML, data: bb, headers: nil);
            }
        }

        return resp!;
    }
}