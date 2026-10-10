import Foundation

/// `ssh -G` output: one lowercase option name and its value per line; some options repeat.
public struct EffectiveOptions: Equatable, Sendable {
    public let values: [String: [String]]

    public init(parsing output: String) {
        var values: [String: [String]] = [:]
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0]).asciiLowercased, default: []].append(String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
        self.values = values
    }

    public func first(_ key: String) -> String? { values[key.asciiLowercased]?.first }

    public var jumpHops: [JumpHop] { first("proxyjump").map(JumpHop.parseList) ?? [] }
}

/// One `ProxyJump` hop: `[user@]host[:port]`, `ssh://[user@]host[:port]`, IPv6 in brackets.
public struct JumpHop: Equatable, Sendable {
    public let user: String?
    public let host: String
    public let port: Int?

    public init(user: String?, host: String, port: Int?) {
        self.user = user
        self.host = host
        self.port = port
    }

    public static func parseList(_ value: String) -> [JumpHop] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.asciiLowercased != "none" else { return [] }
        return trimmed.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    /// As OpenSSH's a2port: an optional `+` then ASCII digits (leading zeros allowed) with value 1...65535,
    /// otherwise a service name known to getservbyname(3) (tcp). Everything else is rejected.
    private static func parsePort(_ text: Substring) -> Int? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return nil }
        let digits = bytes.first == 0x2B ? Array(bytes.dropFirst()) : bytes
        if !digits.isEmpty, digits.allSatisfy({ (0x30...0x39).contains($0) }) {
            var value = 0
            for d in digits {
                value = value * 10 + Int(d - 0x30)
                if value > 65535 { return nil }
            }
            return value >= 1 ? value : nil
        }
        guard bytes.first != 0x2B, let entry = getservbyname(String(text), "tcp") else { return nil }
        let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: entry.pointee.s_port)))
        return port >= 1 ? port : nil
    }

    static func parse(_ text: String) -> JumpHop? {
        var rest = Substring(text)
        if rest.hasPrefix("ssh://") { rest = rest.dropFirst(6) }
        var user: String?
        if let at = rest.lastIndex(of: "@") {
            let name = String(rest[..<at])
            user = name.isEmpty ? nil : name
            rest = rest[rest.index(after: at)...]
        }
        var host: String
        var port: Int?
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            if after.hasPrefix(":") {
                guard let parsed = parsePort(after.dropFirst()) else { return nil }
                port = parsed
            } else if !after.isEmpty {
                return nil
            }
        } else if let colon = rest.lastIndex(of: ":"), rest.filter({ $0 == ":" }).count == 1 {
            host = String(rest[..<colon])
            guard let parsed = parsePort(rest[rest.index(after: colon)...]) else { return nil }
            port = parsed
        } else {
            host = String(rest)
        }
        guard !host.isEmpty else { return nil }
        return JumpHop(user: user, host: host, port: port)
    }
}
