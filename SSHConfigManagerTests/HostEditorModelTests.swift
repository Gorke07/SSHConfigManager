import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostEditorModelTests {
    private func model(_ tmp: TempDir, _ config: String) -> AppModel {
        makeTestModel(tmp, config: config)
    }

    @Test func populatesFieldsFromEntry() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web w2\n  hostname 10.0.0.1\n  User deploy\n  IdentityFile ~/.ssh/a\n  IdentityFile ~/.ssh/b\n  ServerAliveInterval 30\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        #expect(editor.aliasText == "web w2")
        #expect(editor.fields["HostName"] == "10.0.0.1")
        #expect(editor.fields["User"] == "deploy")
        #expect(editor.fields["Port"] == "")
        #expect(editor.identityFiles == ["~/.ssh/a", "~/.ssh/b"])
        #expect(editor.otherOptions == [DraftDirective(key: "ServerAliveInterval", value: "30")])
    }

    @Test func editingAFieldWritesOnlyThatLine() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n\thostname  old # prod\n  User deploy\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.fields["HostName"] = "new.example"
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n\thostname  new.example # prod\n  User deploy\n")
        #expect(app.store.hasUnsavedChanges)
    }

    @Test func renamingFollowsTheItem() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\nHost db\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.aliasText = "web-prod"
        #expect(editor.commit())
        #expect(editor.item == .host(alias: "web-prod", occurrence: 0))
        #expect(app.store.document.hosts.map(\.alias) == ["web-prod", "db"])
    }

    @Test func secondOfDuplicateAliasesIsEditedInPlace() throws {
        let tmp = try TempDir()
        let original = "Host web\n  HostName one\nHost web\n  HostName two\n"
        let app = model(tmp, original)
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 1), store: app.store, homeDirectory: tmp.url))
        #expect(editor.fields["HostName"] == "two")

        // While the alias is still duplicated, edits are blocked and nothing is written.
        editor.fields["HostName"] = "three"
        #expect(!editor.commit())
        #expect(editor.issues.contains(.duplicateAlias("web")))
        #expect(app.store.document.render() == original)

        // Renaming resolves it; only the second block changes.
        editor.aliasText = "web-2"
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n  HostName one\nHost web-2\n  HostName three\n")
        #expect(editor.item == .host(alias: "web-2", occurrence: 0))
    }

    @Test func blockingIssuesPreventWrites() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\nHost db\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))

        editor.fields["Port"] = "99999"
        #expect(!editor.commit())
        #expect(editor.issues == [.invalidPort("99999")])

        editor.fields["Port"] = ""
        editor.aliasText = "db"
        #expect(!editor.commit())
        #expect(editor.issues == [.duplicateAlias("db")])
        #expect(app.store.document.render() == "Host web\n  User u\nHost db\n")
    }

    @Test func pastedLineBreakIsBlocked() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.fields["User"] = "x\nHost evil"
        #expect(!editor.commit())
        #expect(editor.issues.contains(.controlCharacter("User")))
        #expect(app.store.document.render() == "Host web\n  User u\n")
    }

    @Test func missingIdentityFileIsOnlyAWarning() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.identityFiles = ["~/.ssh/missing"]
        #expect(editor.commit())
        #expect(editor.issues == [.identityFileMissing("~/.ssh/missing")])
        #expect(app.store.document.render() == "Host web\n    IdentityFile ~/.ssh/missing\n")
    }

    @Test func otherOptionsAndEmptyRows() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  ServerAliveInterval 30\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.otherOptions = [DraftDirective(key: "ServerAliveInterval", value: "60"), DraftDirective(key: "", value: "")]
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n  ServerAliveInterval 60\n")
    }

    @Test func forwardAgentEmptyMeansUnset() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  ForwardAgent yes\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        #expect(editor.fields["ForwardAgent"] == "yes")
        editor.fields["ForwardAgent"] = ""
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n")
    }

    @Test func staleFormIsNotWrittenOverChangedBlock() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        try app.store.apply { $0 = ConfigDocument(parsing: "Host web\n  User other\n") }
        editor.fields["HostName"] = "x"
        #expect(!editor.commit())
        #expect(editor.isStale)
        #expect(app.store.document.render() == "Host web\n  User other\n")
    }

    @Test func consecutiveCommitsSucceedAndFailureClears() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.fields["Port"] = "99999"
        #expect(!editor.commit())
        editor.fields["Port"] = ""
        editor.fields["User"] = "v"
        #expect(editor.commit())
        #expect(editor.failure == nil)
        editor.fields["Port"] = "22"
        #expect(editor.commit())
        #expect(!editor.isStale)
        #expect(app.store.document.render().contains("User v") && app.store.document.render().contains("Port 22"))
    }

    @Test func nonHostItemsHaveNoEditor() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Match all\n")
        #expect(HostEditorModel(item: .match(index: 0), store: app.store, homeDirectory: tmp.url) == nil)
    }

    @Test func identityFileExistence() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/id_ok", "")
        #expect(HostEditorModel.identityFileExists("~/.ssh/id_ok", home: tmp.url))
        #expect(!HostEditorModel.identityFileExists("~/.ssh/nope", home: tmp.url))
        #expect(HostEditorModel.identityFileExists(tmp.url.appending(path: ".ssh/id_ok").path, home: tmp.url))
        #expect(HostEditorModel.identityFileExists("relative/key", home: tmp.url))   // not checked
    }

    @Test func renameCallsOnItemChangeExactlyOnce() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\nHost db\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        var received: [SidebarItem] = []
        editor.onItemChange = { received.append($0) }
        editor.aliasText = "web-prod"
        #expect(editor.commit())
        #expect(received == [.host(alias: "web-prod", occurrence: 0)])
        // An edit that keeps the identity does not call back.
        editor.fields["HostName"] = "x"
        #expect(editor.commit())
        #expect(received.count == 1)
    }

    @Test func hasPendingChangesTracksBlockedCommits() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        #expect(!editor.hasPendingChanges)
        editor.fields["Port"] = "abc"
        #expect(!editor.commit())
        #expect(editor.hasPendingChanges)
        editor.fields["Port"] = "22"
        #expect(editor.commit())
        #expect(!editor.hasPendingChanges)
        // Reverting a blocked edit back to the baseline is not pending either.
        editor.fields["Port"] = "abc"
        #expect(!editor.commit())
        editor.fields["Port"] = "22"
        #expect(editor.commit())
        #expect(!editor.hasPendingChanges)
    }
}
