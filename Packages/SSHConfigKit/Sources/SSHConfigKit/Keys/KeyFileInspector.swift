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
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2, let fingerprint = Fingerprint.sha256(base64Key: parts[1]) else { return nil }
        type = parts[0]
        base64 = parts[1]
        comment = parts.count > 2 ? parts[2...].joined(separator: " ") : nil
        self.fingerprint = fingerprint
    }
}

/// Looks only at the first bytes of a private key file (header and first base64 line); the key
/// material is never parsed or kept (spec §8.1).
public enum KeyFileError: Error, Equatable, LocalizedError {
    case notARegularFile(String)
    public var errorDescription: String? {
        switch self { case .notARegularFile(let path): "Not a regular file: \(path)" }
    }
}

public enum KeyFileInspector {
    public static let headLimit = 512

    public static func readHead(of url: URL) throws -> Data {
        // O_NONBLOCK: opening a FIFO or device can never block; fstat on the descriptor (no check/use race).
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            close(fd)
            throw KeyFileError.notARegularFile(url.path)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        return try handle.read(upToCount: headLimit) ?? Data()
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
            return lines[1].hasPrefix("Proc-Type:") && lines[1].contains("ENCRYPTED") ? .encrypted : .unencrypted
        }
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
