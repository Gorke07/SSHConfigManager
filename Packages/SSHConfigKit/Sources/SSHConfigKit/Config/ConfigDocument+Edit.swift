public enum ConfigEditError: Error, Equatable, Sendable {
    case hostNotFound(Int)
}

extension ConfigDocument {
    /// Indent of the first directive inside any Host block, else four spaces.
    var directiveIndent: String {
        for entry in hosts {
            for directive in entry.directives {
                if let indent = lines[directive.line].parts?.indent { return indent }
            }
        }
        return "    "
    }

    func makeDirectiveLine(indent: String, key: String, value: String) -> ConfigLine {
        ConfigLine(raw: indent + key + " " + ValueFormatter.encode(key: key, value: value) + lineEndingSuffix)
    }

    /// Applies `draft` to the Host block at `header`, touching only lines whose content changes.
    /// Existing directives are paired with draft directives by key: first matching by value,
    /// then by order for remaining directives.
    public mutating func updateHost(at header: Int, to draft: HostDraft) throws {
        guard let entry = hostEntry(at: header) else { throw ConfigEditError.hostNotFound(header) }
        let end = blockEnd(after: header)

        var replacements: [Int: ConfigLine] = [:]
        var deletions = Set<Int>()
        var insertions: [DraftDirective] = []

        if draft.patterns != entry.patterns, let parts = lines[header].parts {
            replacements[header] = ConfigLine(
                raw: LineTokenizer.replacingValue(in: parts, with: draft.patterns.joined(separator: " ")))
        }

        var existingByKey: [String: [HostDirective]] = [:]
        for directive in entry.directives {
            existingByKey[directive.key.asciiLowercased, default: []].append(directive)
        }
        var draftIndicesByKey: [String: [Int]] = [:]
        for (index, directive) in draft.directives.enumerated() {
            draftIndicesByKey[directive.key.asciiLowercased, default: []].append(index)
        }

        // draft index → the existing directive it updates
        var pairing: [Int: HostDirective] = [:]
        for (key, draftIndices) in draftIndicesByKey {
            var unused = existingByKey[key] ?? []
            var unpaired: [Int] = []
            // Pass 1: equal values pair first and stay untouched.
            for index in draftIndices {
                if let match = unused.firstIndex(where: { $0.value == draft.directives[index].value }) {
                    pairing[index] = unused.remove(at: match)
                } else {
                    unpaired.append(index)
                }
            }
            // Pass 2: the rest pair in order and get their value replaced.
            for (index, old) in zip(unpaired, unused) { pairing[index] = old }
            for old in unused.dropFirst(unpaired.count) { deletions.insert(old.line) }
        }
        for (key, existing) in existingByKey where draftIndicesByKey[key] == nil {
            for old in existing { deletions.insert(old.line) }
        }

        for (index, wanted) in draft.directives.enumerated() {
            guard let old = pairing[index] else {
                insertions.append(wanted)
                continue
            }
            if old.value != wanted.value, let parts = lines[old.line].parts {
                let encoded = ValueFormatter.encode(key: old.key, value: wanted.value)
                replacements[old.line] = ConfigLine(raw: LineTokenizer.replacingValue(in: parts, with: encoded))
            }
        }

        var block: [ConfigLine] = []
        var insertAt = 1
        for i in header..<end where !deletions.contains(i) {
            block.append(replacements[i] ?? lines[i])
            switch lines[i].kind {
            case .directive, .include, .hostStart: insertAt = block.count
            default: break
            }
        }

        let indent = entry.directives.compactMap { lines[$0.line].parts?.indent }.first ?? directiveIndent
        block.insert(
            contentsOf: insertions.map { makeDirectiveLine(indent: indent, key: $0.key, value: $0.value) },
            at: insertAt)
        lines.replaceSubrange(header..<end, with: block)
    }
}
