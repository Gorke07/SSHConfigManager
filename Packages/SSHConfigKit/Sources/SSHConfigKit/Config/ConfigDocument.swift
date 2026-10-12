import Synchronization

/// Line-based, lossless model of an ssh_config file. Untouched lines render
/// exactly as they were read.
public struct ConfigDocument: Equatable, Sendable {
    public internal(set) var lines: [ConfigLine] {
        didSet { derived = Derived() }
    }
    public internal(set) var hasTrailingNewline: Bool
    /// True when the first non-empty line ends with "\r"; new lines follow this convention.
    public let usesCRLF: Bool

    public static let empty = ConfigDocument(parsing: "")

    public init(parsing text: String) {
        // Split on the "\n" byte; "\r\n" is a single Character and must not be split by Character.
        // A UTF-8 BOM stays part of the first line, exactly as ssh reads it.
        var rawLines = text.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }

        if rawLines.count > 1, rawLines.last == "" {
            rawLines.removeLast()
            hasTrailingNewline = true
        } else {
            if rawLines == [""] { rawLines = [] }
            hasTrailingNewline = false
        }

        lines = rawLines.map(ConfigLine.init(raw:))
        usesCRLF = rawLines.first(where: { !$0.isEmpty })?.unicodeScalars.last == "\r"
    }

    public func render() -> String {
        var out = lines.map(\.raw).joined(separator: "\n")
        if hasTrailingNewline { out += "\n" }
        return out
    }

    /// OpenSSH cannot parse a file that starts with a UTF-8 BOM.
    public var hasByteOrderMark: Bool {
        lines.first?.raw.unicodeScalars.first == "\u{FEFF}"
    }

    public mutating func removeByteOrderMark() {
        guard hasByteOrderMark else { return }
        lines[0] = ConfigLine(raw: String(String.UnicodeScalarView(lines[0].raw.unicodeScalars.dropFirst())))
    }

    /// Appended to every newly created line ("\r" for CRLF files).
    var lineEndingSuffix: String { usesCRLF ? "\r" : "" }

    /// Values computed from `lines` on first use. Any change to `lines` installs a fresh box, so copies share
    /// it only while their lines are the same; views can read `hosts` per row without rescanning the file.
    var derived = Derived()

    final class Derived: Sendable {
        struct Values {
            var hosts: [HostEntry]?
            var hostsByAlias: [String: [HostEntry]]?
        }

        let values = Mutex(Values())
    }

    /// The cache is not part of the value.
    public static func == (lhs: ConfigDocument, rhs: ConfigDocument) -> Bool {
        lhs.lines == rhs.lines && lhs.hasTrailingNewline == rhs.hasTrailingNewline && lhs.usesCRLF == rhs.usesCRLF
    }
}
