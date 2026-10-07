import Foundation

public enum KnownHostMarker: String, Equatable, Sendable {
    case certAuthority = "@cert-authority"
    case revoked = "@revoked"
}

/// A plain known_hosts name: `host` (port 22) or `[host]:port`.
public struct KnownHostAddress: Equatable, Sendable {
    public let host: String
    public let port: Int
    /// Wildcards (`*`, `?`) or negation (`!`): never treated as a match for a single host name.
    public let isPattern: Bool

    public init(host: String, port: Int, isPattern: Bool) {
        self.host = host
        self.port = port
        self.isPattern = isPattern
    }
}

public enum KnownHostName: Equatable, Sendable {
    case plain(KnownHostAddress)
    /// `|1|salt|hash`: HMAC-SHA1 of the lookup name, keyed with the salt.
    case hashed(salt: Data, hash: Data)
}

public struct KnownHostEntry: Equatable, Sendable, Identifiable {
    /// Index into `KnownHostsDocument.lines`; stable only for the document it came from.
    public let lineIndex: Int
    public let marker: KnownHostMarker?
    public let names: [KnownHostName]
    public let keyType: String
    public let keyBase64: String
    public let comment: String?

    public var id: Int { lineIndex }

    public var isHashed: Bool {
        names.contains { if case .hashed = $0 { true } else { false } }
    }

    public init(lineIndex: Int, marker: KnownHostMarker?, names: [KnownHostName], keyType: String, keyBase64: String, comment: String?) {
        self.lineIndex = lineIndex
        self.marker = marker
        self.names = names
        self.keyType = keyType
        self.keyBase64 = keyBase64
        self.comment = comment
    }
}
