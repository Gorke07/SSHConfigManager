import Foundation

struct FuzzyMatch: Equatable {
    let score: Int
    /// Character offsets in the alias that matched (for highlighting).
    let aliasOffsets: [Int]
}

/// User-facing host search (spec v1.1 §3): every word must match the alias fuzzily or another
/// field as a substring; case and diacritics are ignored.
/// A query split into folded words once, to be reused across all hosts.
struct FuzzyQuery {
    let words: [String]

    init(_ query: String) {
        words = query.split(whereSeparator: \.isWhitespace).map { FuzzyMatcher.fold(String($0)).joined() }
    }
}

enum FuzzyMatcher {
    /// Folds one character at a time so offsets stay aligned with the original alias.
    /// ASCII characters take a fast path; only other characters go through locale-aware folding.
    static func fold(_ text: String) -> [String] {
        text.map { character -> String in
            if character.isASCII { return character.lowercased() }
            switch character {
            case "ı", "İ": return "i"
            default: return String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
        }
    }

    /// Folds a whole string (no offset alignment needed), mapping Turkish dotted/dotless i to "i" first.
    static func foldWhole(_ text: String) -> String {
        if text.allSatisfy(\.isASCII) { return text.lowercased() }
        let mapped = String(text.map { "ıİI".contains($0) ? Character("i") : $0 })
        return mapped.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func match(query: String, alias: String, others: [String]) -> FuzzyMatch? {
        match(FuzzyQuery(query), alias: alias, others: others)
    }

    static func match(_ query: FuzzyQuery, alias: String, others: [String]) -> FuzzyMatch? {
        let words = query.words
        guard !words.isEmpty else { return FuzzyMatch(score: 0, aliasOffsets: []) }
        let folded = fold(alias)
        let foldedOthers = others.map(foldWhole)
        var score = 0
        var offsets = Set<Int>()
        for word in words {
            if let hit = aliasMatch(Array(word), in: folded) {
                score += hit.score
                offsets.formUnion(hit.offsets)
            } else if foldedOthers.contains(where: { $0.contains(word) }) {
                score += 100
            } else {
                return nil
            }
        }
        return FuzzyMatch(score: score, aliasOffsets: offsets.sorted())
    }

    private static func isWordStart(_ index: Int, in folded: [String]) -> Bool {
        guard index > 0 else { return true }
        let previous = folded[index - 1], current = folded[index]
        if ["-", ".", "_", " "].contains(previous) { return true }
        let previousIsDigit = previous.allSatisfy(\.isNumber), currentIsDigit = current.allSatisfy(\.isNumber)
        return previousIsDigit != currentIsDigit
    }

    private static func aliasMatch(_ word: [Character], in folded: [String]) -> (score: Int, offsets: [Int])? {
        let target = folded.joined()
        let characters = folded.map { $0.first ?? " " }
        if target == String(word) { return (1000, Array(folded.indices)) }
        if target.hasPrefix(String(word)), folded.count >= word.count, folded.allSatisfy({ $0.count == 1 }) {
            return (800, Array(0..<word.count))
        }
        // Word starts: each character continues the previous match or sits at a word start (backtracking).
        func search(_ n: Int, _ position: Int) -> [Int]? {
            if n == word.count { return [] }
            guard position < characters.count else { return nil }
            for index in position..<characters.count where characters[index] == word[n] {
                guard (n > 0 && index == position) || isWordStart(index, in: folded) else { continue }
                if let rest = search(n + 1, index + 1) { return [index] + rest }
            }
            return nil
        }
        if let found = search(0, 0) { return (600, found) }
        var offsets: [Int] = []
        var position = 0
        // Scattered: plain subsequence.
        for character in word {
            guard let index = (position..<characters.count).first(where: { characters[$0] == character }) else { return nil }
            offsets.append(index); position = index + 1
        }
        let gaps = zip(offsets, offsets.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0 - 1) }
        return (300 - min(gaps, 200), offsets)
    }

    static func highlighted(_ alias: String, offsets: [Int]) -> AttributedString {
        var result = AttributedString()
        let wanted = Set(offsets)
        for (index, character) in alias.enumerated() {
            var piece = AttributedString(String(character))
            if wanted.contains(index) { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }
}
