#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

#if os(Linux) || os(macOS)
/// Потокобезопасный вывод в stderr (`write`), чтобы строки не смешивались в Docker без TTY.
public actor ServiceStdio {
    public static let shared = ServiceStdio()
    private var bootstrapped = false

    public func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
    }

    public func log(_ message: String) {
        var line = message
        if !line.hasSuffix("\n") {
            line.append("\n")
        }
        line.withUTF8 { buf in
            guard let base = buf.baseAddress else { return }
            var sent = 0
            let total = buf.count
            while sent < total {
                let n = write(STDERR_FILENO, base + sent, total - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}
#else
public actor ServiceStdio {
    public static let shared = ServiceStdio()
    public func bootstrap() {}
    public func log(_ message: String) {}
}
#endif
