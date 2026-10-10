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
    /// Locale used to fold both the query and the candidates (injectable so tests need not depend on the host's).
    let locale: Locale

    init(_ query: String, locale: Locale = .current) {
        self.locale = locale
        words = query.split(whereSeparator: \.isWhitespace).map { FuzzyMatcher.fold(String($0), locale: locale).joined() }
    }
}

enum FuzzyMatcher {
    /// Folds one character at a time so offsets stay aligned with the original alias.
    /// ASCII characters take a fast path; only other characters go through locale-aware folding.
    static func fold(_ text: String, locale: Locale = .current) -> [String] {
        text.map { character -> String in
            if character.isASCII { return character.lowercased() }
            switch character {
            case "ı", "İ": return "i"
            default: return String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
        }
    }

    /// Folds a whole string (no offset alignment needed), mapping Turkish dotted/dotless i to "i" first.
    static func foldWhole(_ text: String, locale: Locale = .current) -> String {
        if text.allSatisfy(\.isASCII) { return text.lowercased() }
        let mapped = String(text.map { "ıİI".contains($0) ? Character("i") : $0 })
        return mapped.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }

    static func match(query: String, alias: String, others: [String], locale: Locale = .current) -> FuzzyMatch? {
        match(FuzzyQuery(query, locale: locale), alias: alias, others: others)
    }

    static func match(_ query: FuzzyQuery, alias: String, others: [String]) -> FuzzyMatch? {
        let words = query.words
        guard !words.isEmpty else { return FuzzyMatch(score: 0, aliasOffsets: []) }
        let folded = fold(alias, locale: query.locale)
        let foldedOthers = others.map { foldWhole($0, locale: query.locale) }
        // Multi-word queries sum the per-word scores. Every word must match, so all candidates of
        // one query have the same word count and the sums compare like-for-like.
        var score = 0
        var offsets = Set<Int>()
        var steps = 0
        for word in words {
            if let hit = aliasMatch(Array(word), in: folded, steps: &steps) {
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

    /// Test hook: the number of memoized-search steps spent matching one word against an alias.
    static func searchSteps(word: String, alias: String) -> Int {
        var steps = 0
        _ = aliasMatch(Array(foldWhole(word)), in: fold(alias), steps: &steps)
        return steps
    }

    /// Tiers: 1000 exact, 800 prefix, 600 word-start, 101...300 scattered; other-fields hits score 100.
    private static func aliasMatch(_ word: [Character], in folded: [String], steps: inout Int) -> (score: Int, offsets: [Int])? {
        let target = folded.joined()
        let characters = folded.map { $0.first ?? " " }
        if target == String(word) { return (1000, Array(folded.indices)) }
        if target.hasPrefix(String(word)), folded.count >= word.count, folded.allSatisfy({ $0.count == 1 }) {
            return (800, Array(0..<word.count))
        }
        // Word starts: each character continues the previous match or sits at a word start (backtracking).
        var failed = Set<Int>()
        func search(_ n: Int, _ position: Int) -> [Int]? {
            if n == word.count { return [] }
            guard position < characters.count else { return nil }
            let key = n * (characters.count + 1) + position
            if failed.contains(key) { return nil }
            steps += 1  // one per expanded (word index, position) state, so at most word.count x alias.count
            for index in position..<characters.count where characters[index] == word[n] {
                guard (n > 0 && index == position) || isWordStart(index, in: folded) else { continue }
                if let rest = search(n + 1, index + 1) { return [index] + rest }
            }
            failed.insert(key)
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
        return (300 - min(gaps, 199), offsets)
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
