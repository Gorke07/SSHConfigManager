import Testing
@testable import SSHConfigKit

struct AddRemoveHostTests {
    let draft = HostDraft(patterns: ["new"], directives: [DraftDirective(key: "HostName", value: "n.example")])

    @Test func addInsertsBeforeHostStarWithItsComment() throws {
        var doc = ConfigDocument(parsing: "Host a\n  User u\n\n# defaults\nHost *\n  User d\n")
        let header = try doc.addHost(draft)
        #expect(doc.render() == "Host a\n  User u\n\nHost new\n  HostName n.example\n\n# defaults\nHost *\n  User d\n")
        #expect(doc.hostEntry(at: header)?.alias == "new")
    }

    @Test func addInsertsBeforeMatchAll() throws {
        var doc = ConfigDocument(parsing: "Host a\n  User u\nMatch all\n  User d\n")
        let header = try doc.addHost(draft)
        #expect(doc.render() == "Host a\n  User u\n\nHost new\n  HostName n.example\n\nMatch all\n  User d\n")
        #expect(header == 3)
        #expect(doc.hostEntry(at: header)?.alias == "new")
    }

    @Test func addAppendsWhenThereIsNoCatchAll() throws {
        var doc = ConfigDocument(parsing: "Host a\n\tUser u")
        let header = try doc.addHost(draft)
        #expect(doc.render() == "Host a\n\tUser u\n\nHost new\n\tHostName n.example\n")
        #expect(header == 3)
    }

    @Test func addToEmptyDocument() throws {
        var doc = ConfigDocument.empty
        #expect(try doc.addHost(draft) == 0)
        #expect(doc.render() == "Host new\n    HostName n.example\n")
    }

    @Test func addUsesCRLF() throws {
        var doc = ConfigDocument(parsing: "Host a\r\n")
        try doc.addHost(draft)
        #expect(Array(doc.render().utf8) == Array("Host a\r\n\r\nHost new\r\n    HostName n.example\r\n".utf8))
    }

    @Test func removeDeletesAttachedCommentAndKeepsNextHostsComment() throws {
        var doc = ConfigDocument(parsing: "# web\nHost web\n  HostName a\n\n# db\nHost db\n  HostName b\n")
        try doc.removeHost(at: 1)
        #expect(doc.render() == "# db\nHost db\n  HostName b\n")
    }

    @Test func removeLastHostTrimsTrailingBlankLines() throws {
        var doc = ConfigDocument(parsing: "Host a\n  X 1\n\nHost b\n  Y 2\n")
        try doc.removeHost(at: 3)
        #expect(doc.render() == "Host a\n  X 1\n")
    }

    @Test func removeMiddleHostCollapsesBlankLines() throws {
        var doc = ConfigDocument(parsing: "Host a\n\nHost b\n  Y 2\n\nHost c\n")
        try doc.removeHost(at: 2)
        #expect(doc.render() == "Host a\n\nHost c\n")
    }

    @Test func removeOnlyHostLeavesEmptyFile() throws {
        var doc = ConfigDocument(parsing: "Host a\n  X 1\n")
        try doc.removeHost(at: 0)
        #expect(doc.render() == "")
    }

    @Test func footerCommentSurvivesRemovingLastHost() throws {
        var doc = ConfigDocument(parsing: "Host a\n  X 1\n\nHost b\n  Y 2\n\n# footer\n")
        try doc.removeHost(at: 3)
        #expect(doc.render() == "Host a\n  X 1\n\n# footer\n")
    }

    @Test func duplicateInsertsCopyAfterBlock() throws {
        var doc = ConfigDocument(parsing: "Host a # c\n  User u\n\nHost b\n")
        let header = try doc.duplicateHost(at: 0, newAlias: "a-copy")
        #expect(doc.render() == "Host a # c\n  User u\n\nHost a-copy # c\n  User u\n\nHost b\n")
        #expect(doc.hostEntry(at: header)?.alias == "a-copy")
    }

    @Test func removingUnknownHeaderThrows() {
        var doc = ConfigDocument(parsing: "Match all\n")
        #expect(throws: ConfigEditError.hostNotFound(0)) { try doc.removeHost(at: 0) }
    }

    @Test func addHostThrowsOnControlCharacterInDirectiveValue() {
        var doc = ConfigDocument.empty
        let draft = HostDraft(patterns: ["x"], directives: [DraftDirective(key: "User", value: "a\nHost evil")])
        #expect(throws: ConfigEditError.controlCharacter) { try doc.addHost(draft) }
        #expect(doc.render() == "")
    }

    @Test func duplicateHostThrowsOnControlCharacterInAlias() throws {
        var doc = ConfigDocument(parsing: "Host a\n  User u\n")
        #expect(throws: ConfigEditError.controlCharacter) { try doc.duplicateHost(at: 0, newAlias: "a\nb") }
    }
}
