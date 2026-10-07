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

        // Group existing directives by key
        var existingByKey: [String: [HostDirective]] = [:]
        for directive in entry.directives {
            existingByKey[directive.key.asciiLowercased, default: []].append(directive)
        }

        // Track which existing lines and draft indices have been paired
        var pairedLines: Set<Int> = []
        var pairedDraftIndices: Set<Int> = []

        // First pass: pair draft directives with existing directives having the same value
        for (draftIdx, wanted) in draft.directives.enumerated() {
            let key = wanted.key.asciiLowercased
            if let existing = existingByKey[key] {
                for old in existing {
                    if !pairedLines.contains(old.line) && old.value == wanted.value {
                        pairedLines.insert(old.line)
                        pairedDraftIndices.insert(draftIdx)
                        break
                    }
                }
            }
        }

        // Second pass: pair remaining draft directives in order with remaining existing ones
        var usedByKey: [String: Int] = [:]
        for (draftIdx, wanted) in draft.directives.enumerated() {
            // Skip if already paired in first pass
            if pairedDraftIndices.contains(draftIdx) { continue }

            let key = wanted.key.asciiLowercased

            if let existing = existingByKey[key] {
                let n = usedByKey[key, default: 0]
                var foundCount = 0
                for old in existing {
                    if !pairedLines.contains(old.line) {
                        if foundCount == n {
                            pairedLines.insert(old.line)
                            pairedDraftIndices.insert(draftIdx)
                            usedByKey[key] = n + 1
                            break
                        }
                        foundCount += 1
                    }
                }
            }
        }

        // Now pair lines to draft directives
        var lineToWanted: [Int: DraftDirective] = [:]
        var wantedUsedByKey: [String: Int] = [:]

        for directive in entry.directives {
            if pairedLines.contains(directive.line) {
                let key = directive.key.asciiLowercased
                let n = wantedUsedByKey[key, default: 0]

                // Find the n-th draft directive with this key
                var count = 0
                for (idx, wanted) in draft.directives.enumerated() {
                    if wanted.key.asciiLowercased == key {
                        if count == n {
                            lineToWanted[directive.line] = wanted
                            wantedUsedByKey[key] = n + 1
                            break
                        }
                        count += 1
                    }
                }
            }
        }

        // Apply replacements where values differ
        for (line, wanted) in lineToWanted {
            if let old = entry.directives.first(where: { $0.line == line }) {
                if old.value != wanted.value, let parts = lines[line].parts {
                    let encoded = ValueFormatter.encode(key: old.key, value: wanted.value)
                    replacements[line] = ConfigLine(raw: LineTokenizer.replacingValue(in: parts, with: encoded))
                }
            }
        }

        // Identify insertions: draft directives not paired with any line
        for (idx, wanted) in draft.directives.enumerated() {
            if !pairedDraftIndices.contains(idx) {
                insertions.append(wanted)
            }
        }

        // Mark unpaired existing directives for deletion
        for directive in entry.directives {
            if !pairedLines.contains(directive.line) {
                deletions.insert(directive.line)
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
