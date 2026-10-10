import Foundation

struct FuzzyMatch: Equatable {
    let score: Int
    /// Character offsets in the alias that matched (for highlighting).
    let aliasOffsets: [Int]
}

/// User-facing host search (spec v1.1 §3): every word must match the alias fuzzily or another
/// field as a substring; case and diacritics are ignored.
enum FuzzyMatcher {
    /// Folds one character at a time so offsets stay aligned with the original alias.
    static func fold(_ text: String) -> [String] {
        text.map { character -> String in
            switch character {
            case "ı", "I", "İ": "i"
            default: String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
        }
    }

    static func match(query: String, alias: String, others: [String]) -> FuzzyMatch? {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)).joined() }
        guard !words.isEmpty else { return FuzzyMatch(score: 0, aliasOffsets: []) }
        let folded = fold(alias)
        let foldedOthers = others.map { fold($0).joined() }
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
        // Word starts: each character continues the previous match or jumps to the next word start.
        var offsets: [Int] = []
        var position = 0
        var ok = true
        for (n, character) in word.enumerated() {
            if n > 0, let last = offsets.last, last + 1 < characters.count, characters[last + 1] == character {
                offsets.append(last + 1); position = last + 2; continue
            }
            guard let index = (position..<characters.count).first(where: { characters[$0] == character && isWordStart($0, in: folded) }) else {
                ok = false; break
            }
            offsets.append(index); position = index + 1
        }
        if ok { return (600, offsets) }
        // Scattered: plain subsequence.
        offsets = []
        position = 0
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
