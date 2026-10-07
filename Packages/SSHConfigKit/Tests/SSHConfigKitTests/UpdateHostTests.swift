import Testing
@testable import SSHConfigKit

struct UpdateHostTests {
    private func update(_ text: String, header: Int = 0, _ change: (inout HostDraft) -> Void) throws -> String {
        var doc = ConfigDocument(parsing: text)
        var draft = HostDraft(try #require(doc.hostEntry(at: header)))
        change(&draft)
        try doc.updateHost(at: header, to: draft)
        return doc.render()
    }

    private func set(_ draft: inout HostDraft, _ key: String, _ value: String) {
        let index = draft.directives.firstIndex { $0.key == key }!
        draft.directives[index].value = value
    }

    @Test func unchangedDraftIsByteIdentical() throws {
        let text = "Host a b # c\n\tHostName  h # x\n  IdentityFile \"~/a b\"\n  User=u\n"
        let out = try update(text) { _ in }
        #expect(Array(out.utf8) == Array(text.utf8))
    }

    @Test func changingValueKeepsIndentSeparatorAndComment() throws {
        let out = try update("Host web\n\tHostName  old.example # prod\n  User u\n") {
            set(&$0, "HostName", "new.example")
        }
        #expect(out == "Host web\n\tHostName  new.example # prod\n  User u\n")
    }

    @Test func equalsSeparatorIsKept() throws {
        let out = try update("Host a\n  User=u\n") { set(&$0, "User", "v") }
        #expect(out == "Host a\n  User=v\n")
    }

    @Test func addedDirectiveGoesAfterLastDirective() throws {
        let out = try update("Host a\n  User u\n\n# b\nHost b\n") {
            $0.directives.append(DraftDirective(key: "Port", value: "22"))
        }
        #expect(out == "Host a\n  User u\n  Port 22\n\n# b\nHost b\n")
    }

    @Test func addedDirectiveInEmptyBlockUsesDocumentIndent() throws {
        let out = try update("Host a\nHost b\n\tUser u\n") {
            $0.directives.append(DraftDirective(key: "User", value: "x"))
        }
        #expect(out == "Host a\n\tUser x\nHost b\n\tUser u\n")
    }

    @Test func removingDirectiveDeletesOnlyThatLine() throws {
        let out = try update("Host a\n  User u\n  Port 22\n  # keep\n") {
            $0.directives.removeAll { $0.key == "Port" }
        }
        #expect(out == "Host a\n  User u\n  # keep\n")
    }

    @Test func repeatedKeysArePairedInOrder() throws {
        let out = try update("Host a\n  IdentityFile k1\n  IdentityFile k2\n") {
            $0.directives.removeLast()
        }
        #expect(out == "Host a\n  IdentityFile k1\n")
    }

    @Test func renamingAliasKeepsOtherPatternsAndComment() throws {
        let out = try update("Host a a2 # c\n  User u\n") { $0.patterns[0] = "x" }
        #expect(out == "Host x a2 # c\n  User u\n")
    }

    @Test func valuesWithSpacesAreQuoted() throws {
        let out = try update("Host a\n  IdentityFile ~/k\n") { set(&$0, "IdentityFile", "~/My Keys/k") }
        #expect(out == "Host a\n  IdentityFile \"~/My Keys/k\"\n")
    }

    @Test func crlfDocumentGetsCRLFOnNewLines() throws {
        let out = try update("Host a\r\n  User u\r\n") {
            $0.directives.append(DraftDirective(key: "Port", value: "22"))
        }
        #expect(Array(out.utf8) == Array("Host a\r\n  User u\r\n  Port 22\r\n".utf8))
    }

    @Test func mixedLineEndingsOfUntouchedLinesSurvive() throws {
        let out = try update("Host a\r\n  User u\n  Port 1\r\n") { set(&$0, "Port", "2") }
        #expect(Array(out.utf8) == Array("Host a\r\n  User u\n  Port 2\r\n".utf8))
    }

    @Test func unknownHeaderThrows() {
        var doc = ConfigDocument(parsing: "User x\n")
        #expect(throws: ConfigEditError.hostNotFound(0)) {
            try doc.updateHost(at: 0, to: HostDraft(patterns: ["a"]))
        }
    }

    @Test func removingFirstOfRepeatedKeysDeletesCorrectLine() throws {
        let out = try update("Host a\n  IdentityFile k1 # first\n  IdentityFile k2 # second\n") {
            $0.directives.removeAll { $0.value == "k1" }
        }
        #expect(out == "Host a\n  IdentityFile k2 # second\n")
    }

    @Test func changingMiddleOfThreeRepeatedKeysOnlyChangesMiddle() throws {
        let out = try update("Host a\n  IdentityFile k1\n  IdentityFile k2\n  IdentityFile k3\n") {
            let index = $0.directives.firstIndex { $0.value == "k2" }!
            $0.directives[index].value = "kx"
        }
        #expect(out == "Host a\n  IdentityFile k1\n  IdentityFile kx\n  IdentityFile k3\n")
    }

    @Test func insertionAtEndOfFileWithoutTrailingNewline() throws {
        let out = try update("Host a\n  User u") {
            $0.directives.append(DraftDirective(key: "Port", value: "22"))
        }
        #expect(out == "Host a\n  User u\n  Port 22")
    }
}
