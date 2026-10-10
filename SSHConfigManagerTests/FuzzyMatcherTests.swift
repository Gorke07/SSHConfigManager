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

    @Test func highlightingMakesMatchedCharactersBold() {
        let text = FuzzyMatcher.highlighted("prod", offsets: [0, 3])
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
        #expect(bold == ["p", "d"])
    }
}
