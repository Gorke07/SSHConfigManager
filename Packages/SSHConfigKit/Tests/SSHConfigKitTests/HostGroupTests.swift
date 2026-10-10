import Foundation
import Testing
@testable import SSHConfigKit

struct HostGroupTests {
    @Test(arguments: [
        ("# group: Production", "Production"),
        ("#group:prod", "prod"),
        ("   # GROUP :  Prod  ", "Prod"),
        ("# Group: Staging Servers\r", "Staging Servers"),
        ("# group:", ""),
    ])
    func parsesGroupComments(_ line: String, _ expected: String) {
        #expect(ConfigDocument.groupName(inCommentLine: line) == expected)
    }

    @Test(arguments: ["# groups: x", "# my group: x", "Host x", "# group x", ""])
    func ignoresOtherLines(_ line: String) {
        #expect(ConfigDocument.groupName(inCommentLine: line) == nil)
    }

    @Test func readsTheNearestGroupInTheGluedCommentBlock() {
        let doc = ConfigDocument(parsing: """
        # group: Old
        # web servers
        # group: Production
        Host web
          HostName 10.0.0.1

        # group: Detached

        Host db
        # group: Inside
        Host cache

        """)
        #expect(doc.group(ofHostAt: 3) == "Production")
        #expect(doc.group(ofHostAt: 8) == nil)                  // separated by a blank line
        #expect(doc.group(ofHostAt: 10) == "Inside")
    }

    @Test func emptyNameMeansNoGroup() {
        let doc = ConfigDocument(parsing: "# group:\nHost a\n")
        #expect(doc.group(ofHostAt: 1) == nil)
    }

    @Test func settingAddsChangesAndRemovesOnlyTheGroupLine() throws {
        let original = "# keep me\nHost a\n  User u\n\nHost b\n"
        var doc = ConfigDocument(parsing: original)
        try doc.setGroup(ofHostAt: 1, to: "  Prod ")
        #expect(doc.render() == "# keep me\n# group: Prod\nHost a\n  User u\n\nHost b\n")
        try doc.setGroup(ofHostAt: 2, to: "Staging")
        #expect(doc.render() == "# keep me\n# group: Staging\nHost a\n  User u\n\nHost b\n")
        try doc.setGroup(ofHostAt: 2, to: nil)
        #expect(doc.render().utf8.elementsEqual(original.utf8))
        try doc.setGroup(ofHostAt: 1, to: "")                    // no group line and nothing to add
        #expect(doc.render().utf8.elementsEqual(original.utf8))
    }

    @Test func crlfFilesGetCRLFGroupLines() throws {
        var doc = ConfigDocument(parsing: "Host a\r\n  User u\r\n")
        try doc.setGroup(ofHostAt: 0, to: "x")
        #expect(doc.render() == "# group: x\r\nHost a\r\n  User u\r\n")
    }

    @Test func refusesControlCharactersAndNonHosts() {
        var doc = ConfigDocument(parsing: "Host a\nMatch all\n")
        #expect(throws: ConfigEditError.controlCharacter) { try doc.setGroup(ofHostAt: 0, to: "a\nb") }
        #expect(throws: ConfigEditError.hostNotFound(1)) { try doc.setGroup(ofHostAt: 1, to: "x") }
    }

    @Test func removingAHostRemovesItsGroupLine() throws {
        var doc = ConfigDocument(parsing: "# group: g\nHost a\n\nHost b\n")
        try doc.removeHost(at: 1)
        #expect(doc.render() == "Host b\n")
    }
}
