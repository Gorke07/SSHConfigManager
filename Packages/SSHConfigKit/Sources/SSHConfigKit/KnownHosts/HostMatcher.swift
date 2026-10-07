import CryptoKit
import Foundation

/// Finds known_hosts entries for one host, the way `ssh-keygen -F` does.
public enum HostMatcher {
    /// ssh's lookup form: `host` for port 22, `[host]:port` otherwise; the host is ASCII-lowercased.
    public static func lookupName(host: String, port: Int) -> String {
        let lower = host.asciiLowercased
        return port == 22 ? lower : "[\(lower)]:\(port)"
    }

    private static let hostScalars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:".unicodeScalars)

    /// Parses a search query that looks like one host (`host`, `host:port`, `[host]:port`, IPv6);
    /// returns nil for anything else (spaces, wildcards, slashes, …).
    public static func lookupName(forQuery query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("[") {
            guard let address = KnownHostsDocument.parseAddress(text), !address.isPattern,
                  isHost(address.host) else { return nil }
            return lookupName(host: address.host, port: address.port)
        }
        guard isHost(text) else { return nil }
        let colons = text.filter { $0 == ":" }.count
        if colons == 1, let colon = text.firstIndex(of: ":") {
            let host = String(text[..<colon])
            guard isHost(host), !host.contains(":"),
                  let port = Int(text[text.index(after: colon)...]), (1...65535).contains(port) else { return nil }
            return lookupName(host: host, port: port)
        }
        return lookupName(host: text, port: 22)   // plain host or IPv6 literal
    }

    private static func isHost(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(hostScalars.contains)
            && text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    public static func matches(_ name: KnownHostName, lookupName: String) -> Bool {
        switch name {
        case .plain(let address):
            // Patterns are never a match for one host: deleting them would drop wider trust.
            guard !address.isPattern else { return false }
            return Self.lookupName(host: address.host, port: address.port) == lookupName.asciiLowercased
        case .hashed(let salt, let hash):
            let code = HMAC<Insecure.SHA1>.authenticationCode(for: Data(lookupName.utf8), using: SymmetricKey(data: salt))
            return Data(code) == hash
        }
    }

    /// Entries (no markers: `@cert-authority` / `@revoked` lines are not host keys) with a name
    /// matching any of `lookupNames`.
    public static func entries(in document: KnownHostsDocument, matchingAny lookupNames: [String]) -> [KnownHostEntry] {
        document.entries.filter { entry in
            entry.marker == nil && entry.names.contains { name in lookupNames.contains { matches(name, lookupName: $0) } }
        }
    }
}
