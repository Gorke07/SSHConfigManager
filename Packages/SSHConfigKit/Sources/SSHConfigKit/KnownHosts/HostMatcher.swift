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
            // The bracket form is kept as written: `[host]:22` is not `host` (ssh-keygen -F).
            return "[\(address.host.asciiLowercased)]:\(address.port)"
        }
        guard isHost(text) else { return nil }
        let colons = text.filter { $0 == ":" }.count
        if colons == 1, let colon = text.firstIndex(of: ":") {
            let host = String(text[..<colon])
            guard isHost(host), !host.contains(":"),
                  let port = Int(text[text.index(after: colon)...]), (1...65535).contains(port) else { return nil }
            return lookupName(host: host, port: port)
        }
        if colons >= 2 {
            // Several colons: only a real IPv6 literal is a host (`a:b:c` is not).
            var buffer = in6_addr()
            guard inet_pton(AF_INET6, text, &buffer) == 1 else { return nil }
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
            // The literal form, as ssh-keygen compares it: a `[host]:22` line is not a match for `host`.
            return address.literal.asciiLowercased == lookupName.asciiLowercased
        case .hashed(let salt, let hash):
            let code = HMAC<Insecure.SHA1>.authenticationCode(for: Data(lookupName.utf8), using: SymmetricKey(data: salt))
            return Data(code) == hash
        }
    }

    /// Entries (no markers: `@cert-authority` / `@revoked` lines are not host keys) with a name
    /// matching any of `lookupNames`.
    public static func entries(in document: KnownHostsDocument, matchingAny lookupNames: [String]) -> [KnownHostEntry] {
        document.entries.filter { entry in
            entry.marker == nil && lookupNames.contains { lookup in
                entry.names.contains { matches($0, lookupName: lookup) } && !isNegated(lookup, in: entry)
            }
        }
    }

    /// ssh's match_hostname: a `!name` on the line that matches the lookup name makes the whole line a
    /// non-match (`!host,host` is never found by `ssh-keygen -F host`).
    private static func isNegated(_ lookupName: String, in entry: KnownHostEntry) -> Bool {
        entry.names.contains { name in
            guard case .plain(let address) = name, address.literal.hasPrefix("!") else { return false }
            // Wildcards in the negated pattern count (`host,!h*st` vetoes `host`), case-sensitive like ssh's match_pattern.
            return ConfigResolver.wildcardMatch(String(address.literal.dropFirst()).asciiLowercased, lookupName.asciiLowercased)
        }
    }
}
