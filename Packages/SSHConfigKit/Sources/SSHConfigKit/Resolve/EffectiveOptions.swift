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

    static func parse(_ text: String) -> JumpHop? {
        var rest = Substring(text)
        if rest.hasPrefix("ssh://") { rest = rest.dropFirst(6) }
        var user: String?
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at])
            rest = rest[rest.index(after: at)...]
        }
        var host: String
        var port: Int?
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            if after.hasPrefix(":") { port = Int(after.dropFirst()) }
        } else if let colon = rest.lastIndex(of: ":"), rest.filter({ $0 == ":" }).count == 1 {
            host = String(rest[..<colon])
            port = Int(rest[rest.index(after: colon)...])
        } else {
            host = String(rest)
        }
        guard !host.isEmpty else { return nil }
        if let port, !(1...65535).contains(port) { return nil }
        return JumpHop(user: user, host: host, port: port)
    }
}
