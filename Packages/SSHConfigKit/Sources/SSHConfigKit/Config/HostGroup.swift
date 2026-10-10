import Foundation

/// Groups are `# group: <name>` comment lines in the comment block glued to a `Host` line
/// (ssh ignores them). The line nearest to the Host wins.
extension ConfigDocument {
    /// The group name in a comment line, "" for `# group:` with no name, nil if not a group line.
    public static func groupName(inCommentLine raw: String) -> String? {
        var text = Substring(raw)
        if text.hasSuffix("\r") { text = text.dropLast() }
        text = text.drop { $0 == " " || $0 == "\t" }
        guard text.first == "#" else { return nil }
        text = text.dropFirst().drop { $0 == " " || $0 == "\t" }
        guard text.prefix(5).asciiLowercased == "group" else { return nil }
        text = text.dropFirst(5).drop { $0 == " " || $0 == "\t" }
        guard text.first == ":" else { return nil }
        return text.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    /// Index of the group line in the comment block directly above `header`, if any.
    func groupLineIndex(above header: Int) -> Int? {
        var index = header - 1
        while index >= 0, lines[index].kind == .comment {
            if Self.groupName(inCommentLine: lines[index].raw) != nil { return index }
            index -= 1
        }
        return nil
    }

    public func group(ofHostAt header: Int) -> String? {
        guard hostEntry(at: header) != nil, let index = groupLineIndex(above: header),
              let name = Self.groupName(inCommentLine: lines[index].raw), !name.isEmpty else { return nil }
        return name
    }

    /// Adds, replaces or (nil / empty name) removes the Host's group line; no other line changes.
    public mutating func setGroup(ofHostAt header: Int, to name: String?) throws {
        guard hostEntry(at: header) != nil else { throw ConfigEditError.hostNotFound(header) }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmed.containsControlCharacter else { throw ConfigEditError.controlCharacter }
        let line = ConfigLine(raw: "# group: " + trimmed + lineEndingSuffix)
        if let index = groupLineIndex(above: header) {
            if trimmed.isEmpty { lines.remove(at: index) } else { lines[index] = line }
        } else if !trimmed.isEmpty {
            lines.insert(line, at: header)
        }
    }
}
