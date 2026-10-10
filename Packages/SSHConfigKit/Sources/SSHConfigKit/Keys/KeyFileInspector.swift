import Foundation

public enum KeyEncryption: Equatable, Sendable {
    case encrypted
    case unencrypted
    /// Not a recognizable private key head, or no private key at all.
    case unknown
}

/// A `.pub` file's first line: `type base64 [comment]`.
public struct PublicKeyInfo: Equatable, Sendable {
    public let type: String
    public let base64: String
    public let comment: String?
    public let fingerprint: String

    public init?(text: String) {
        let lines = text.unicodeScalars.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map { String(String.UnicodeScalarView($0)) }
        guard let line = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        // type, base64, then the comment exactly as written (inner spacing kept).
        func isBlank(_ c: Character) -> Bool { c == " " || c == "\t" }
        var rest = Substring(line)
        func field() -> String? {
            rest = rest.drop(while: isBlank)
            let word = rest.prefix { !isBlank($0) }
            rest = rest.dropFirst(word.count)
            return word.isEmpty ? nil : String(word)
        }
        guard let typeField = field(), let blob = field(),
              Self.blobType(base64: blob) == typeField,
              let fingerprint = Fingerprint.sha256(base64Key: blob) else { return nil }
        var remainder = rest.drop(while: isBlank)
        while let last = remainder.last, isBlank(last) { remainder = remainder.dropLast() }
        type = typeField
        base64 = blob
        comment = remainder.isEmpty ? nil : String(remainder)
        self.fingerprint = fingerprint
    }
}

extension PublicKeyInfo {
    /// The key type name the blob itself starts with (uint32 length + string), nil if malformed.
    static func blobType(base64: String) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let bytes = Array(data.prefix(4 + 64))
        guard bytes.count >= 4 else { return nil }
        let length = bytes[0..<4].reduce(0) { $0 << 8 | Int($1) }
        guard (1...64).contains(length), bytes.count >= 4 + length else { return nil }
        return String(decoding: bytes[4..<4 + length], as: UTF8.self)
    }
}

public enum KeyFileError: Error, Equatable, LocalizedError {
    case notARegularFile(String)
    public var errorDescription: String? {
        switch self { case .notARegularFile(let path): "Not a regular file: \(path)" }
    }
}

/// Looks only at the first bytes of a private key file (header and first base64 line); the key
/// material is never parsed or kept (spec §8.1).
public enum KeyFileInspector {
    public static let headLimit = 512

    public static func readHead(of url: URL) throws -> Data {
        try RegularFile.read(url, limit: headLimit)
    }

    /// Lines split on LF bytes, a trailing CR removed.
    static func lines(_ head: Data) -> [String] {
        head.split(separator: 0x0A, omittingEmptySubsequences: false).map { slice in
            var bytes = Array(slice)
            if bytes.last == 0x0D { bytes.removeLast() }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    public static func isPrivateKeyHeader(_ head: Data) -> Bool {
        guard let first = lines(head).first else { return false }
        return first.hasPrefix("-----BEGIN ") && first.hasSuffix("PRIVATE KEY-----")
    }

    public static func encryption(ofPrivateKeyHead head: Data) -> KeyEncryption {
        guard isPrivateKeyHeader(head) else { return .unknown }
        let lines = lines(head)
        switch lines[0] {
        case "-----BEGIN OPENSSH PRIVATE KEY-----":
            guard lines.count > 1, let cipher = openSSHCipher(firstBase64Line: lines[1]) else { return .unknown }
            return cipher == "none" ? .unencrypted : .encrypted
        case "-----BEGIN ENCRYPTED PRIVATE KEY-----":
            return .encrypted
        case "-----BEGIN PRIVATE KEY-----":
            return .unencrypted
        default:   // traditional PEM: RSA / EC / DSA
            guard lines.count > 1 else { return .unknown }
            return Self.isEncryptedProcType(lines[1]) ? .encrypted : .unencrypted
        }
    }

    /// `Proc-Type: 4,ENCRYPTED` exactly (spaces around the fields allowed).
    static func isEncryptedProcType(_ line: String) -> Bool {
        guard line.hasPrefix("Proc-Type:") else { return false }
        let fields = line.dropFirst("Proc-Type:".count).split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return fields == ["4", "ENCRYPTED"]
    }

    /// openssh-key-v1: magic "openssh-key-v1\0", then a uint32 (big endian) length and the cipher name.
    static func openSSHCipher(firstBase64Line line: String) -> String? {
        let usable = String(line.prefix(line.utf8.count / 4 * 4))
        guard let data = Data(base64Encoded: usable) else { return nil }
        let bytes = Array(data)
        let magic = Array("openssh-key-v1".utf8) + [0]
        let lengthStart = magic.count
        let nameStart = lengthStart + 4
        guard bytes.count >= nameStart, Array(bytes[0..<magic.count]) == magic else { return nil }
        let length = bytes[lengthStart..<nameStart].reduce(0) { $0 << 8 | Int($1) }
        guard (1...64).contains(length), bytes.count >= nameStart + length else { return nil }
        return String(decoding: bytes[nameStart..<nameStart + length], as: UTF8.self)
    }
}
