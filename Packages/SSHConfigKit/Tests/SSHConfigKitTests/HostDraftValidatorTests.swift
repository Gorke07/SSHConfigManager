import Testing
@testable import SSHConfigKit

struct HostDraftValidatorTests {
    let doc = ConfigDocument(parsing: "Host web web2\n  User u\nHost *.prod\nHost db\n")
    let validator = HostDraftValidator(fileExists: { $0 == "~/.ssh/id_ok" })

    private func issues(_ draft: HostDraft, editing: Int? = nil) -> [DraftIssue] {
        validator.issues(for: draft, in: doc, editing: editing)
    }

    @Test func validDraftHasNoIssues() {
        let draft = HostDraft(patterns: ["new"], directives: [
            DraftDirective(key: "Port", value: "2222"),
            DraftDirective(key: "IdentityFile", value: "~/.ssh/id_ok"),
        ])
        #expect(issues(draft).isEmpty)
    }

    @Test func aliasRules() {
        #expect(issues(HostDraft(patterns: [])) == [.emptyAlias])
        #expect(issues(HostDraft(patterns: [""])) == [.emptyAlias])
        #expect(issues(HostDraft(patterns: ["a b"])) == [.aliasHasWhitespace])
        #expect(issues(HostDraft(patterns: ["web2"])) == [.duplicateAlias("web2")])
        #expect(issues(HostDraft(patterns: ["WEB2"])) == [.duplicateAliasCaseOnly("WEB2")])
        #expect(!DraftIssue.duplicateAliasCaseOnly("WEB2").isBlocking)
    }

    @Test func editingItselfIsNotADuplicate() {
        #expect(issues(HostDraft(patterns: ["web", "web2"]), editing: 0).isEmpty)
        #expect(issues(HostDraft(patterns: ["db"]), editing: 0) == [.duplicateAlias("db")])
    }

    @Test func wildcardPatternsNeverCountAsDuplicates() {
        #expect(issues(HostDraft(patterns: ["*.prod"])).isEmpty)
    }

    @Test(arguments: ["0", "65536", "abc", "22 23", "", "+22", " 22"])
    func invalidPorts(port: String) {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "port", value: port)]))
        #expect(found.contains(.invalidPort(port)))
    }

    @Test func validPortWithLeadingZeros() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "port", value: "022")]))
        #expect(found.isEmpty)
    }

    @Test func directiveKeyRules() {
        let draft = HostDraft(patterns: ["n"], directives: [
            DraftDirective(key: "Bad Key", value: "x"),
            DraftDirective(key: "Host", value: "x"),
            DraftDirective(key: "INCLUDE", value: "x"),
            DraftDirective(key: "User", value: "  "),
        ])
        #expect(issues(draft) == [
            .invalidDirectiveKey("Bad Key"),
            .forbiddenDirectiveKey("Host"),
            .forbiddenDirectiveKey("INCLUDE"),
            .emptyDirectiveValue("User"),
        ])
    }

    @Test func missingIdentityFileIsANonBlockingWarning() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "IdentityFile", value: "~/.ssh/nope")]))
        #expect(found == [.identityFileMissing("~/.ssh/nope")])
        #expect(found.allSatisfy { !$0.isBlocking })
    }

    @Test func identityFileWithTokensIsNotChecked() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "IdentityFile", value: "~/.ssh/%h")]))
        #expect(found.isEmpty)
    }

    @Test func controlCharacterInAlias() {
        let found = issues(HostDraft(patterns: ["a\nb"]))
        #expect(found == [.controlCharacter("a\nb")])
    }

    @Test func controlCharacterInDirectiveValue() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "User", value: "x\nHost evil")]))
        #expect(found.contains(.controlCharacter("User")))
    }

    @Test func tabInDirectiveValueIsAllowed() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "User", value: "x\ty")]))
        #expect(found.isEmpty)
    }

    @Test func duplicateAliasesWithinDraft() {
        #expect(issues(HostDraft(patterns: ["a", "a"])) == [.duplicateAlias("a")])
        #expect(issues(HostDraft(patterns: ["a", "A"])) == [.duplicateAliasCaseOnly("A")])
    }

    @Test func editingAHostBesideItsCaseVariantOrExactTwinIsNotBlocked() {
        let variant = ConfigDocument(parsing: "Host web\n  User a\nHost Web\n  User b\n")
        let draft = HostDraft(patterns: ["web"], directives: [DraftDirective(key: "User", value: "changed")])
        #expect(validator.issues(for: draft, in: variant, editing: variant.hosts[0].headerLine).isEmpty)
        #expect(validator.issues(for: HostDraft(patterns: ["Web"]), in: variant, editing: variant.hosts[1].headerLine).isEmpty)

        let twin = ConfigDocument(parsing: "Host web\n  User a\nHost web\n  User b\n")
        #expect(validator.issues(for: draft, in: twin, editing: twin.hosts[1].headerLine).isEmpty)
    }

    @Test func repeatsWithinTheDraftAreFlaggedEvenForTheBlocksOwnAlias() {
        let doc = ConfigDocument(parsing: "Host web\n")
        let editing = doc.hosts[0].headerLine
        #expect(validator.issues(for: HostDraft(patterns: ["web", "web"]), in: doc, editing: editing) == [.duplicateAlias("web")])
        #expect(validator.issues(for: HostDraft(patterns: ["web", "Web"]), in: doc, editing: editing) == [.duplicateAliasCaseOnly("Web")])
    }

    @Test func renamingOntoAnExistingExactAliasIsStillRejected() {
        let two = ConfigDocument(parsing: "Host web\nHost other\n")
        #expect(validator.issues(for: HostDraft(patterns: ["web"]), in: two, editing: two.hosts[1].headerLine) == [.duplicateAlias("web")])
    }

    @Test func addingACaseVariantBesideAnExistingHostDoesNotBlock() {
        let one = ConfigDocument(parsing: "Host web\n")
        let found = validator.issues(for: HostDraft(patterns: ["Web"]), in: one, editing: nil)
        #expect(found == [.duplicateAliasCaseOnly("Web")])
        #expect(found.allSatisfy { !$0.isBlocking })
    }

    @Test func controlCharacterInPortValue() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "Port", value: "22\n")]))
        #expect(found.contains(.controlCharacter("Port")))
    }

    @Test func repeatedSingleValueKeyWarnsOnce() {
        let draft = HostDraft(patterns: ["new"], directives: [
            DraftDirective(key: "User", value: "a"),
            DraftDirective(key: "user", value: "b"),
            DraftDirective(key: "User", value: "c"),
            DraftDirective(key: "IdentityFile", value: "~/.ssh/id_ok"),
            DraftDirective(key: "IdentityFile", value: "~/.ssh/id_ok"),
        ])
        #expect(issues(draft) == [.duplicateFieldKey("User")])
        #expect(!DraftIssue.duplicateFieldKey("User").isBlocking)
    }
}
