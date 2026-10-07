public enum ConfigEditError: Error, Equatable, Sendable {
    case hostNotFound(Int)
    case controlCharacter
}

// MARK: - Helpers

private func containsControlCharacter(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
        let value = scalar.value
        return (value >= 0x00 && value <= 0x1F && value != 0x09) || value == 0x7F
    }
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

        // Check for control characters in patterns and directives
        for pattern in draft.patterns {
            if containsControlCharacter(pattern) { throw ConfigEditError.controlCharacter }
        }
        for directive in draft.directives {
            if containsControlCharacter(directive.key) || containsControlCharacter(directive.value) {
                throw ConfigEditError.controlCharacter
            }
        }

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

    /// `Host *` or `Match all`: ssh uses the first value it finds, so new hosts must come before these.
    private func isCatchAll(_ index: Int) -> Bool {
        switch lines[index].kind {
        case .hostStart(let patterns): patterns == ["*"]
        case .matchStart(let criteria): criteria.asciiLowercased == "all"
        default: false
        }
    }

    @discardableResult
    public mutating func addHost(_ draft: HostDraft) throws -> Int {
        // Check for control characters in patterns and directives
        for pattern in draft.patterns {
            if containsControlCharacter(pattern) { throw ConfigEditError.controlCharacter }
        }
        for directive in draft.directives {
            if containsControlCharacter(directive.key) || containsControlCharacter(directive.value) {
                throw ConfigEditError.controlCharacter
            }
        }

        let indent = directiveIndent
        let blank = ConfigLine(raw: lineEndingSuffix)
        var hostLines = [ConfigLine(raw: "Host " + draft.patterns.joined(separator: " ") + lineEndingSuffix)]
        hostLines += draft.directives.map { makeDirectiveLine(indent: indent, key: $0.key, value: $0.value) }

        if let catchAll = headerIndices.first(where: isCatchAll) {
            var position = catchAll
            while position > 0 && lines[position - 1].kind == .comment { position -= 1 }
            let lead = (position > 0 && lines[position - 1].kind != .blank) ? [blank] : []
            lines.insert(contentsOf: lead + hostLines + [blank], at: position)
            return position + lead.count
        }

        if let last = lines.last, last.kind != .blank { lines.append(blank) }
        let header = lines.count
        lines += hostLines
        hasTrailingNewline = true
        return header
    }

    public mutating func removeHost(at header: Int) throws {
        guard hostEntry(at: header) != nil else { throw ConfigEditError.hostNotFound(header) }
        var start = header
        while start > 0 && lines[start - 1].kind == .comment { start -= 1 }
        lines.removeSubrange(start..<ownedEnd(of: header))

        while start < lines.count, lines[start].kind == .blank, start == 0 || lines[start - 1].kind == .blank {
            lines.remove(at: start)
        }
        if start == lines.count {
            while lines.last?.kind == .blank { lines.removeLast() }
        }
        if lines.isEmpty { hasTrailingNewline = false }
    }

    @discardableResult
    public mutating func duplicateHost(at header: Int, newAlias: String) throws -> Int {
        guard hostEntry(at: header) != nil, let parts = lines[header].parts else {
            throw ConfigEditError.hostNotFound(header)
        }

        if containsControlCharacter(newAlias) { throw ConfigEditError.controlCharacter }

        var end = ownedEnd(of: header)
        while end - 1 > header && lines[end - 1].kind == .blank { end -= 1 }

        var copy = Array(lines[header..<end])
        copy[0] = ConfigLine(raw: LineTokenizer.replacingValue(in: parts, with: newAlias))
        lines.insert(contentsOf: [ConfigLine(raw: lineEndingSuffix)] + copy, at: end)
        return end + 1
    }
}
