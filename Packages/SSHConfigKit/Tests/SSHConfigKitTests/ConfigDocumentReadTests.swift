import Testing
@testable import SSHConfigKit

struct ConfigDocumentReadTests {
    let sample = """
    # global
    User me
    Include config.d/*

    # web sunucusu
    Host web web2
        HostName 10.0.0.1
        IdentityFile "~/My Keys/id"
        IdentityFile ~/.ssh/second

    HOST *.prod
      user deploy

    Match host x exec "true"
      Port 2200

    Host *
        ServerAliveInterval 30

    """

    @Test func parsesHostsWithDisplayValues() throws {
        let doc = ConfigDocument(parsing: sample)
        #expect(doc.hosts.map(\.patterns) == [["web", "web2"], ["*.prod"], ["*"]])
        let web = try #require(doc.hosts.first)
        #expect(web.alias == "web")
        #expect(web.headerLine == 5)
        #expect(!web.isPattern)
        #expect(web.value(for: "hostname") == "10.0.0.1")
        #expect(web.values(for: "IDENTITYFILE") == ["~/My Keys/id", "~/.ssh/second"])
        #expect(web.directives.map(\.line) == [6, 7, 8])
    }

    @Test func patternsAreFlagged() {
        let doc = ConfigDocument(parsing: "Host a\nHost *.x\nHost ?b\nHost !c d\nHost\n")
        #expect(doc.hosts.map(\.isPattern) == [false, true, true, true, true])
    }

    @Test func matchesIncludesAndGlobals() throws {
        let doc = ConfigDocument(parsing: sample)
        let match = try #require(doc.matches.first)
        #expect(match.criteria == "host x exec \"true\"")
        #expect(match.text == "Match host x exec \"true\"\n  Port 2200")
        #expect(doc.includes == [IncludeDirective(line: 2, paths: ["config.d/*"])])
        #expect(doc.globalDirectives.map(\.key) == ["User"])
    }

    @Test func uppercaseKeywordsAreRecognized() {
        let doc = ConfigDocument(parsing: "INCLUDE x\nHOST a\n  IDENTITYFILE k\n")
        #expect(doc.includes.count == 1)
        #expect(doc.hosts.first?.value(for: "IdentityFile") == "k")
    }

    @Test func blockBoundaries() {
        let doc = ConfigDocument(parsing: "Host a\n  X 1\n\n# b\nHost b\n  Y 2\n# trailing\n")
        #expect(doc.headerIndices == [0, 4])
        #expect(doc.blockEnd(after: 0) == 4)
        // The "# b" comment belongs to the next host, not to "a".
        #expect(doc.ownedEnd(of: 0) == 3)
        #expect(doc.ownedEnd(of: 4) == 7)
    }

    @Test func blockBoundariesAtEndOfFile() {
        let doc = ConfigDocument(parsing: "Host a\n  X 1\n\n# footer\n")
        // The "# footer" comment is unowned (separated by blank line).
        #expect(doc.ownedEnd(of: 0) == 2)
    }

    @Test func matchFooterAtEndOfFile() {
        let doc = ConfigDocument(parsing: "Match all\n  Port 1\n\n# footer\n")
        let match = doc.matches.first
        #expect(match?.text == "Match all\n  Port 1")
    }

    @Test func valueFormatter() {
        #expect(ValueFormatter.display(key: "IdentityFile", rawValue: "\"~/a b\"") == "~/a b")
        #expect(ValueFormatter.display(key: "LocalForward", rawValue: "8080 \"h:80\"") == "8080 \"h:80\"")
        #expect(ValueFormatter.encode(key: "identityfile", value: "~/a b") == "\"~/a b\"")
        #expect(ValueFormatter.encode(key: "IdentityFile", value: "~/ab") == "~/ab")
        #expect(ValueFormatter.encode(key: "LocalForward", value: "8080 h:80") == "8080 h:80")
        // Broken quote handling
        #expect(ValueFormatter.encode(key: "IdentityFile", value: "\"a b") == "\"\"a b\"")
        #expect(ValueFormatter.encode(key: "IdentityFile", value: "\"~/a b\"") == "\"~/a b\"")
        #expect(ValueFormatter.encode(key: "IdentityFile", value: "") == "")
    }
}
