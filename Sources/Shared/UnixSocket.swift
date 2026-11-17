import Foundation

/// Shared POSIX unix-domain-socket helpers for HerdrAppBar's own socket,
/// which `herdrappbar-open` writes to: newline-delimited JSON, one object per
/// line, blocking with an explicit timeout.
enum UnixSocket {

    /// `sun_path` is a fixed 104-byte buffer on Darwin; longer paths cannot be
    /// represented at all, so reject them instead of silently truncating into a
    /// wrong path.
    static let maxPathLength = 103

    /// Connect to `path`, returning a socket fd with send/recv timeouts armed.
    static func connect(path: String, timeout: TimeInterval) -> Int32? {
        let bytes = Array(path.utf8)
        guard bytes.count <= maxPathLength else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }

        setTimeouts(fd, timeout)

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) == 0 }
        }
        guard ok else { close(fd); return nil }
        return fd
    }

    /// Bind + listen on `path`, replacing a stale socket file left behind by a
    /// crashed process. Returns nil when another *live* process already owns it,
    /// which is how HerdrBar enforces a single instance.
    static func listen(path: String, backlog: Int32 = 16) -> Int32? {
        let bytes = Array(path.utf8)
        guard bytes.count <= maxPathLength else { return nil }

        // A socket file that still accepts connections means a live owner.
        if FileManager.default.fileExists(atPath: path) {
            if let probe = connect(path: path, timeout: 0.5) {
                close(probe)
                return nil
            }
            try? FileManager.default.removeItem(atPath: path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) == 0 }
        }
        guard bound, Darwin.listen(fd, backlog) == 0 else { close(fd); return nil }

        // Owner-only: these sockets accept commands that spawn terminals.
        chmod(path, 0o600)
        return fd
    }

    static func setTimeouts(_ fd: Int32, _ timeout: TimeInterval) {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        let buf = [UInt8](data)
        var off = 0
        while off < buf.count {
            let n = buf.withUnsafeBytes { raw -> Int in
                Darwin.send(fd, raw.baseAddress!.advanced(by: off), buf.count - off, 0)
            }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    /// Read up to the next `\n` and return the line without it. Returns nil on
    /// timeout or a peer that closed before sending anything. Reads in chunks:
    /// every connection here carries a single line, so nothing after the
    /// newline is lost.
    static func readLine(_ fd: Int32, limit: Int = 8 * 1024 * 1024) -> Data? {
        var out = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while out.count < limit {
            let n = chunk.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { return out.isEmpty ? nil : out }
            if let newline = chunk[0 ..< n].firstIndex(of: 0x0A) {
                out.append(contentsOf: chunk[0 ..< newline])
                return out
            }
            out.append(contentsOf: chunk[0 ..< n])
        }
        return out
    }

    static func request(path: String, json: [String: Any], timeout: TimeInterval = 3) -> [String: Any]? {
        guard let fd = connect(path: path, timeout: timeout) else { return nil }
        defer { close(fd) }
        guard var payload = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        payload.append(0x0A)
        guard writeAll(fd, payload), let line = readLine(fd) else { return nil }
        return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    @discardableResult
    static func send(path: String, json: [String: Any], timeout: TimeInterval = 1) -> Bool {
        guard let fd = connect(path: path, timeout: timeout) else { return false }
        defer { close(fd) }
        guard var payload = try? JSONSerialization.data(withJSONObject: json) else { return false }
        payload.append(0x0A)
        return writeAll(fd, payload)
    }
}

/// Filesystem locations shared by the app and the CLI.
enum Paths {
    static var supportDir: String {
        NSHomeDirectory() + "/Library/Application Support/dev.herdr.appbar"
    }

    static var barSocket: String { supportDir + "/bar.sock" }
    static var configFile: String { supportDir + "/config.json" }

    static func ensureSupportDir() {
        try? FileManager.default.createDirectory(
            atPath: supportDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
}
