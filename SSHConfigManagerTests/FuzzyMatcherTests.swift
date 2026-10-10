import Foundation
import Testing
@testable import SSH_Config_Manager

struct FuzzyMatcherTests {
    @Test func tiersOrderResults() throws {
        let exact = try #require(FuzzyMatcher.match(query: "web", alias: "web", others: []))
        let prefix = try #require(FuzzyMatcher.match(query: "web", alias: "web-01", others: []))
        let wordStart = try #require(FuzzyMatcher.match(query: "pw", alias: "prod-web", others: []))
        let scattered = try #require(FuzzyMatcher.match(query: "prd", alias: "prod-web-01", others: []))
        let other = try #require(FuzzyMatcher.match(query: "10.0", alias: "db", others: ["10.0.0.5"]))
        #expect(exact.score > prefix.score && prefix.score > wordStart.score && wordStart.score > scattered.score && scattered.score > other.score)
    }

    @Test func everyWordMustMatch() {
        #expect(FuzzyMatcher.match(query: "prd web", alias: "prod-web-01", others: []) != nil)
        #expect(FuzzyMatcher.match(query: "prd xyz", alias: "prod-web-01", others: []) == nil)
        #expect(FuzzyMatcher.match(query: "prd ubuntu", alias: "prod-web-01", others: ["ubuntu"]) != nil)
    }

    @Test func offsetsPointAtTheMatchedCharacters() throws {
        #expect(try #require(FuzzyMatcher.match(query: "pw", alias: "prod-web", others: [])).aliasOffsets == [0, 5])
        #expect(try #require(FuzzyMatcher.match(query: "prd", alias: "prod-web-01", others: [])).aliasOffsets == [0, 1, 3])
        #expect(try #require(FuzzyMatcher.match(query: "web", alias: "web-01", others: [])).aliasOffsets == [0, 1, 2])
    }

    @Test func caseAndDiacriticsAreIgnored() throws {
        #expect(FuzzyMatcher.match(query: "istanbul", alias: "İSTANBUL-db", others: []) != nil)
        #expect(FuzzyMatcher.match(query: "isik", alias: "ışık", others: []) != nil)
        let match = try #require(FuzzyMatcher.match(query: "db", alias: "İSTANBUL-db", others: []))
        #expect(match.aliasOffsets == [9, 10])
    }

    /// The folding locale is injected, so the result never depends on the machine running the tests.
    @Test(arguments: ["en_US_POSIX", "tr_TR"])
    func foldingGivesTheSameMatchesInEveryLocale(identifier: String) throws {
        let locale = Locale(identifier: identifier)
        #expect(FuzzyMatcher.match(query: "istanbul", alias: "İSTANBUL-db", others: [], locale: locale) != nil)
        #expect(FuzzyMatcher.match(query: "ISTANBUL", alias: "istanbul-db", others: [], locale: locale) != nil)
        #expect(FuzzyMatcher.match(query: "isik", alias: "ışık", others: [], locale: locale) != nil)
        #expect(FuzzyMatcher.match(query: "gokhan", alias: "web", others: ["Gökhan"], locale: locale) != nil)
        let match = try #require(FuzzyMatcher.match(query: "db", alias: "İSTANBUL-db", others: [], locale: locale))
        #expect(match.aliasOffsets == [9, 10])
    }

    /// Proves the injected locale is really used: "Ì" folds to "i" in en_US_POSIX but to the dotless "ı" in tr_TR.
    @Test func foldUsesTheInjectedLocale() {
        #expect(FuzzyMatcher.fold("Ì", locale: Locale(identifier: "en_US_POSIX")) == ["i"])
        #expect(FuzzyMatcher.fold("Ì", locale: Locale(identifier: "tr_TR")) == ["ı"])
        #expect(FuzzyMatcher.match(query: "Ìx", alias: "Ìx", others: [], locale: Locale(identifier: "tr_TR")) != nil)
    }

    @Test func highlightingMakesMatchedCharactersBold() {
        let text = FuzzyMatcher.highlighted("prod", offsets: [0, 3])
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
        #expect(bold == ["p", "d"])
    }

    @Test func wordStartBacktracks() throws {
        let match = try #require(FuzzyMatcher.match(query: "wea", alias: "web-eat", others: []))
        #expect(match.score == 600)
        #expect(match.aliasOffsets == [0, 4, 5])
    }

    @Test func eszettKeepsOffsetsInRange() throws {
        let match = try #require(FuzzyMatcher.match(query: "s", alias: "straße", others: []))
        #expect(match.aliasOffsets.allSatisfy { $0 < "straße".count })
        let tail = try #require(FuzzyMatcher.match(query: "e", alias: "straße", others: []))
        #expect(tail.aliasOffsets == [5])
        #expect(FuzzyMatcher.match(query: "s", alias: "ß", others: []) != nil)
    }

    @Test func adjacentOffsetsFormOneBoldRun() {
        let text = FuzzyMatcher.highlighted("web-01", offsets: [0, 1, 2])
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
        #expect(bold == ["web"])
    }

    @Test func emojiInAlias() throws {
        let match = try #require(FuzzyMatcher.match(query: "prod", alias: "🚀prod", others: []))
        #expect(match.aliasOffsets == [1, 2, 3, 4])
        let text = FuzzyMatcher.highlighted("🚀prod", offsets: match.aliasOffsets)
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
        #expect(bold == ["prod"])
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.match(query: "  ", alias: "web", others: []) == FuzzyMatch(score: 0, aliasOffsets: []))
    }

    @Test func queryOverloadMatchesStringOverload() {
        for query in ["prd web", "pw", "isik", "xyz", "10.0", ""] {
            let prepared = FuzzyQuery(query)
            for alias in ["prod-web-01", "ışık", "db"] {
                #expect(FuzzyMatcher.match(prepared, alias: alias, others: ["10.0.0.5"]) == FuzzyMatcher.match(query: query, alias: alias, others: ["10.0.0.5"]))
            }
        }
    }

    @Test func pathologicalAliasStaysPolynomial() {
        let alias = Array(repeating: "a", count: 40).joined(separator: "-")
        let word = "aaaaaaaaaaaaaaaab"
        let steps = FuzzyMatcher.searchSteps(word: word, alias: alias)
        #expect(steps <= alias.count * word.count * 4, "steps: \(steps)")
        let clock = ContinuousClock()
        var result: FuzzyMatch?
        let elapsed = clock.measure { result = FuzzyMatcher.match(query: word, alias: alias, others: []) }
        #expect(result == nil)
        #expect(elapsed < .seconds(5))  // hang guard only
        let scattered = FuzzyMatcher.match(query: "aaaaaaaaaaaaaaaa", alias: alias, others: [])
        #expect(scattered != nil)
    }

    @Test func scatteredAliasMatchOutranksOtherFieldsEvenOverManyGaps() throws {
        let alias = "a" + String(repeating: "x", count: 300) + "b"
        let scattered = try #require(FuzzyMatcher.match(query: "ab", alias: alias, others: []))
        let other = try #require(FuzzyMatcher.match(query: "ab", alias: "zzz", others: ["ab.example.com"]))
        #expect(scattered.score == 101)
        #expect(scattered.score > other.score)
    }

    @Test func multiWordAliasMatchOutranksHostNameOnlyMatch() throws {
        let both = try #require(FuzzyMatcher.match(query: "prod web", alias: "prod-web", others: []))
        let viaHostName = try #require(FuzzyMatcher.match(query: "prod web", alias: "prod-db", others: ["web.example.com"]))
        #expect(both.score > viaHostName.score)
    }
}
