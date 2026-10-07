import Foundation

public enum KnownHostsLineKind: Equatable, Sendable {
    case blank
    case comment
    case entry(KnownHostEntry)
    /// Kept byte-for-byte and shown with ⚠.
    case unparsable
}

/// Line-based, lossless known_hosts model: `render()` returns the parsed text byte for byte.
public struct KnownHostsDocument: Sendable {
    public struct Line: Sendable {
        /// The line including its terminator ("\n" or "\r\n"; none for a last line without newline).
        public let raw: String
        public let kind: KnownHostsLineKind
    }

    public private(set) var lines: [Line]

    public static let empty = KnownHostsDocument(parsing: "")

    public init(parsing text: String) {
        var result: [Line] = []
        let bytes = Array(text.utf8)
        var start = 0
        var index = 0
        while start < bytes.count {
            var end = start
            while end < bytes.count && bytes[end] != 0x0A { end += 1 }
            let hasNewline = end < bytes.count
            let rawEnd = hasNewline ? end + 1 : end
            let raw = String(decoding: bytes[start..<rawEnd], as: UTF8.self)
            var contentEnd = end
            if contentEnd > start && bytes[contentEnd - 1] == 0x0D { contentEnd -= 1 }
            let content = String(decoding: bytes[start..<contentEnd], as: UTF8.self)
            result.append(Line(raw: raw, kind: Self.classify(content, lineIndex: index)))
            start = rawEnd
            index += 1
        }
        lines = result
    }

    public var entries: [KnownHostEntry] {
        lines.compactMap { if case .entry(let entry) = $0.kind { entry } else { nil } }
    }

    /// Unparsable lines with their index and text (without the terminator).
    public var unparsableLines: [(index: Int, text: String)] {
        lines.enumerated().compactMap { index, line in
            guard line.kind == .unparsable else { return nil }
            return (index, Self.content(of: line.raw))
        }
    }

    public func render() -> String {
        lines.map(\.raw).joined()
    }

    /// Removes the given line indices (unknown indices are ignored) and re-parses so entry
    /// line indices stay consistent. Other lines keep their exact bytes.
    public mutating func remove(lines indices: Set<Int>) {
        let kept = lines.enumerated().filter { !indices.contains($0.offset) }.map(\.element.raw)
        self = KnownHostsDocument(parsing: kept.joined())
    }

    /// A line's text without its terminator.
    public static func content(of raw: String) -> String {
        var bytes = Array(raw.utf8)
        if bytes.last == 0x0A { bytes.removeLast() }
        if bytes.last == 0x0D { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func classify(_ content: String, lineIndex: Int) -> KnownHostsLineKind {
        if content.unicodeScalars.first == "\u{FEFF}" { return .unparsable }
        let tokens = content.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = tokens.first else { return .blank }
        if first.unicodeScalars.first == "#" { return .comment }

        var rest = tokens[...]
        var marker: KnownHostMarker?
        if first.unicodeScalars.first == "@" {
            guard let parsed = KnownHostMarker(rawValue: first) else { return .unparsable }
            marker = parsed
            rest = rest.dropFirst()
        }
        guard rest.count >= 3 else { return .unparsable }
        let hostField = rest[rest.startIndex]
        let keyType = rest[rest.startIndex + 1]
        let key = rest[rest.startIndex + 2]
        guard Data(base64Encoded: key) != nil, let names = parseNames(hostField) else { return .unparsable }
        let commentTokens = rest.dropFirst(3)
        return .entry(KnownHostEntry(
            lineIndex: lineIndex, marker: marker, names: names, keyType: keyType, keyBase64: key,
            comment: commentTokens.isEmpty ? nil : commentTokens.joined(separator: " ")))
    }

    static func parseNames(_ field: String) -> [KnownHostName]? {
        if field.unicodeScalars.first == "|" {
            // Hashed names are always alone on the line: |1|salt|hash
            let parts = field.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0].isEmpty, parts[1] == "1",
                  let salt = Data(base64Encoded: String(parts[2])), !salt.isEmpty,
                  let hash = Data(base64Encoded: String(parts[3])), !hash.isEmpty
            else { return nil }
            return [.hashed(salt: salt, hash: hash)]
        }
        var names: [KnownHostName] = []
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            guard let address = parseAddress(String(part)) else { return nil }
            names.append(.plain(address))
        }
        return names
    }

    static func parseAddress(_ text: String) -> KnownHostAddress? {
        guard !text.isEmpty else { return nil }
        let isPattern = text.unicodeScalars.first == "!" || text.contains("*") || text.contains("?")
        if text.unicodeScalars.first == "[" {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let after = text[text.index(after: close)...]
            let digits = after.unicodeScalars.dropFirst()
            guard !host.isEmpty, after.unicodeScalars.first == ":",
                  !digits.isEmpty, digits.allSatisfy({ ("0"..."9").contains($0) }),
                  let port = Int(String(after.dropFirst())), (1...65535).contains(port) else { return nil }
            return KnownHostAddress(host: host, port: port, isPattern: isPattern)
        }
        return KnownHostAddress(host: text, port: 22, isPattern: isPattern)
    }
}
