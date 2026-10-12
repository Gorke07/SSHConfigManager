import Testing
@testable import SSHConfigKit

struct LineTokenizerTests {
    @Test func blankAndCommentLines() {
        #expect(LineTokenizer.classify("") == .blank)
        #expect(LineTokenizer.classify(" \t ") == .blank)
        #expect(LineTokenizer.classify("\r") == .blank)
        #expect(LineTokenizer.classify("  # yorum") == .comment)
        #expect(LineTokenizer.classify("#Host x") == .comment)
    }

    @Test(arguments: [
        "Host web",
        "    HostName 10.0.0.1",
        "\tUser=deploy",
        "Port = 2222",
        "IdentityFile \"~/My Keys/id\"  # anahtar",
        "ProxyJump bastion\r",
        "Host",
        "Key  #c",
        "Host e\u{301}",
    ])
    func partsReassembleToRaw(raw: String) throws {
        let parts = try #require(LineTokenizer.classify(raw).parts)
        #expect(Array(parts.raw.utf8) == Array(raw.utf8))
    }

    @Test func splitsIntoIndentKeySeparatorValueTrailing() throws {
        let p = try #require(LineTokenizer.classify("  Port = 2222 # ssh\r").parts)
        #expect(p.indent == "  ")
        #expect(p.key == "Port")
        #expect(p.separator == " = ")
        #expect(p.value == "2222")
        #expect(p.trailing == " # ssh\r")
    }

    @Test func hashInsideTokenIsNotAComment() throws {
        let p = try #require(LineTokenizer.classify("Host foo#bar").parts)
        #expect(p.value == "foo#bar")
        #expect(p.trailing == "")
    }

    @Test func quotedValueMayContainHash() throws {
        let p = try #require(LineTokenizer.classify("IdentityFile \"~/a #b\" # c").parts)
        #expect(p.value == "\"~/a #b\"")
        #expect(p.trailing == " # c")
    }

    @Test(arguments: ["=foo", "Ho:st x", "-x y"])
    func unknownLines(raw: String) {
        #expect(LineTokenizer.classify(raw) == .unknown)
    }

    @Test func argumentsRespectQuotes() {
        #expect(LineTokenizer.arguments(of: "a  \"b c\" d") == ["a", "b c", "d"])
        #expect(LineTokenizer.arguments(of: "\"\"") == [""])
        #expect(LineTokenizer.arguments(of: "") == [])
    }

    @Test func replacingValueKeepsLayout() throws {
        let p1 = try #require(LineTokenizer.classify("\tHostName  old # prod\r").parts)
        #expect(LineTokenizer.replacingValue(in: p1, with: "new") == "\tHostName  new # prod\r")

        let p2 = try #require(LineTokenizer.classify("User=u").parts)
        #expect(LineTokenizer.replacingValue(in: p2, with: "v") == "User=v")

        let p3 = try #require(LineTokenizer.classify("Host").parts)
        #expect(LineTokenizer.replacingValue(in: p3, with: "a") == "Host a")

        let p4 = try #require(LineTokenizer.classify("Key  #c").parts)
        #expect(LineTokenizer.replacingValue(in: p4, with: "v") == "Key  v #c")
    }

    @Test func asciiLowercasedIgnoresLocale() {
        #expect("INCLUDE".asciiLowercased == "include")
        #expect("IdentityFile".asciiLowercased == "identityfile")
        #expect("İstanbul".asciiLowercased == "İstanbul")
    }

    @Test func startsCommentFindsUnquotedHashAtWordStart() {
        #expect(LineTokenizer.startsComment("x #bc"))
        #expect(LineTokenizer.startsComment("#x"))
        #expect(LineTokenizer.startsComment("\"a\" #b"))
        #expect(!LineTokenizer.startsComment("x#bc"))
        #expect(!LineTokenizer.startsComment("\"x #bc\""))
        #expect(!LineTokenizer.startsComment(""))
    }

    @Test func replacingWithACommentStartingValueDropsTheOldComment() throws {
        let parts = try #require(LineTokenizer.classify("  LocalCommand x #b\r").parts)
        #expect(LineTokenizer.replacingValue(in: parts, with: "x #bc") == "  LocalCommand x #bc\r")
        #expect(LineTokenizer.replacingValue(in: parts, with: "y") == "  LocalCommand y #b\r")
    }
}
