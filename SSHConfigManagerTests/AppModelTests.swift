import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct AppModelTests {
    @Test func settingsDefaultsAndPersistence() throws {
        let tmp = try TempDir()
        let settings = AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url)
        #expect(settings.configPath == "~/.ssh/config")
        #expect(settings.backupCount == 10)
        #expect(settings.configURL == tmp.url.appending(path: ".ssh/config"))

        settings.setConfigPath("~/dotfiles/ssh/config")
        settings.setBackupCount(99)
        let reloaded = AppSettings(defaults: UserDefaults(suiteName: tmp.defaultsSuiteName)!, homeDirectory: tmp.url)
        #expect(reloaded.configPath == "~/dotfiles/ssh/config")
        #expect(reloaded.backupCount == 50)
    }

    @Test func expandAndDisplayPaths() throws {
        let tmp = try TempDir()
        let home = URL(filePath: "/Users/test")
        #expect(AppSettings.expand("~", home: home) == home)
        #expect(AppSettings.expand("~/a/b", home: home) == home.appending(path: "a/b"))
        #expect(AppSettings.expand("/etc/ssh/x", home: home) == URL(filePath: "/etc/ssh/x"))
        let settings = AppSettings(defaults: tmp.defaults, homeDirectory: home)
        #expect(settings.displayPath(for: home.appending(path: ".ssh/config")) == "~/.ssh/config")
        #expect(settings.displayPath(for: URL(filePath: "/opt/x")) == "/opt/x")
    }

    @Test func modelLoadsConfiguredFile() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        #expect(model.store.loadState == .loaded)
        #expect(model.store.document.hosts.map(\.alias) == ["a"])
        #expect(model.commandBuilder.usesDefaultConfig)
    }

    @Test func switchingConfigWithUnsavedChangesNeedsConfirmation() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        try model.store.apply { _ = try $0.addHost(HostDraft(patterns: ["new"])) }
        let original = model.store

        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path) == .needsConfirmation)
        #expect(model.store === original)
        #expect(model.settings.configPath == "~/.ssh/config")

        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path, discardingUnsavedChanges: true) == .switched)
        #expect(model.store.document.hosts.map(\.alias) == ["b"])
        #expect(model.selection == nil)
        #expect(!model.commandBuilder.usesDefaultConfig)
    }

    @Test func switchingConfigWithBlockedFormEditsNeedsConfirmation() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        let editor = try #require(model.editor(for: a))
        editor.fields["Port"] = "abc"
        #expect(!editor.commit())
        #expect(model.hasPendingFormEdits)
        #expect(!model.store.hasUnsavedChanges)

        let other = tmp.url.appending(path: "other/config").path
        #expect(model.switchConfig(to: other) == .needsConfirmation)
        #expect(model.settings.configPath == "~/.ssh/config")
        #expect(model.switchConfig(to: other, discardingUnsavedChanges: true) == .switched)
    }

    @Test func switchingToTheSameFileIsUnchanged() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let original = model.store
        #expect(model.switchConfig(to: "~/.ssh/config") == .unchanged)
        #expect(model.store === original)
    }

    @Test func backupCountReachesStoreAndManager() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        model.setBackupCount(3)
        #expect(model.settings.backupCount == 3)
        #expect(model.backupManager.keep == 3)
        #expect(model.store.backupKeep == 3)
    }

    @Test func selectionTokens() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let first = model.editorToken
        model.select(.host(alias: "a", occurrence: 0))
        let afterSelect = model.editorToken
        #expect(afterSelect != first)
        model.followRename(to: .host(alias: "b", occurrence: 0))
        #expect(model.selection == .host(alias: "b", occurrence: 0))
        #expect(model.editorToken == afterSelect)   // rename keeps the editor alive
        model.resetEditor()
        #expect(model.editorToken != afterSelect)
    }

    @Test func invalidPathsAreRejected() throws {
        #expect(AppSettings.isValidConfigPath("/etc/x"))
        #expect(AppSettings.isValidConfigPath("~"))
        #expect(AppSettings.isValidConfigPath("~/a"))
        for bad in ["", "   ", "relative/config", "~bob/x"] {
            #expect(!AppSettings.isValidConfigPath(bad))
        }
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let original = model.store
        for bad in ["", "relative/config", "~bob/x"] {
            #expect(model.switchConfig(to: bad) == .invalid)
            #expect(model.store === original)
            #expect(model.settings.configPath == "~/.ssh/config")
        }
    }

    @Test func invalidStoredPathFallsBackToDefault() throws {
        let tmp = try TempDir()
        tmp.defaults.set("relative/config", forKey: "configPath")
        let settings = AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url)
        #expect(settings.configPath == "~/.ssh/config")
    }

    @Test func oldStoreIsReleasedOnSwitch() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        weak let old = model.store
        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path, discardingUnsavedChanges: true) == .switched)
        #expect(old == nil)
    }

    @Test func requestSelectWithoutPendingEditsSelectsDirectly() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        let b = SidebarItem.host(alias: "b", occurrence: 0)
        model.requestSelect(b)
        #expect(model.selection == b)
        #expect(model.pendingSelection == nil)
    }

    @Test func requestSelectWithPendingEditsAsksFirst() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        let b = SidebarItem.host(alias: "b", occurrence: 0)
        model.select(a)
        let token = model.editorToken
        let editor = try #require(model.editor(for: a))
        editor.fields["Port"] = "abc"
        #expect(!editor.commit())
        #expect(model.hasPendingFormEdits)

        model.requestSelect(b)
        #expect(model.pendingSelection == b)
        #expect(model.selection == a)
        #expect(model.editorToken == token)

        model.cancelPendingSelection()
        #expect(model.pendingSelection == nil)
        #expect(model.selection == a)

        model.requestSelect(b)
        model.confirmPendingSelection()
        #expect(model.selection == b)
        #expect(model.pendingSelection == nil)
        #expect(model.editorToken != token)
    }

    @Test func editorSurvivesWindowCloseAndKeepsPendingEdits() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        let first = try #require(model.editor(for: a))
        #expect(model.editor(for: a) === first)
        first.fields["Port"] = "abc"
        #expect(!first.commit())

        // Window closed and reopened: the view asks again with the same token.
        let again = try #require(model.editor(for: a))
        #expect(again === first)
        #expect(again.hasPendingChanges)
        #expect(model.hasPendingFormEdits)
        #expect(again.fields["Port"] == "abc")
    }

    @Test func selectingOrResettingDropsTheEditor() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        let b = SidebarItem.host(alias: "b", occurrence: 0)
        model.select(a)
        let first = try #require(model.editor(for: a))
        first.fields["Port"] = "abc"
        _ = first.commit()
        model.select(b)
        #expect(model.activeEditor == nil)
        #expect(!model.hasPendingFormEdits)

        let second = try #require(model.editor(for: b))
        model.resetEditor()
        #expect(model.activeEditor == nil)
        let third = try #require(model.editor(for: b))
        #expect(third !== second)
    }

    @Test func editorFollowsRenameThroughTheModel() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        let editor = try #require(model.editor(for: a))
        let token = model.editorToken
        editor.aliasText = "a2"
        #expect(editor.commit())
        #expect(model.selection == .host(alias: "a2", occurrence: 0))
        #expect(model.editorToken == token)
        #expect(model.editor(for: .host(alias: "a2", occurrence: 0)) === editor)
    }

    @Test func switchingConfigClearsSearchAndError() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        model.searchText = "a"
        model.errorMessage = "x"
        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(model.searchText.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func connectionResultsAreClearedAfterSaveAndReload() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n  HostName 10.0.0.1\n")
        await model.connectionTests.test("a", using: model.commandBuilder)
        #expect(model.connectionTests.results["a"] != nil)

        // Editing alone keeps the result (it still describes the saved file)...
        try model.store.apply { doc in
            let entry = doc.hosts[0]
            var draft = HostDraft(entry)
            draft.directives = [DraftDirective(key: "HostName", value: "10.0.0.2")]
            try doc.updateHost(at: entry.headerLine, to: draft)
        }
        #expect(model.connectionTests.results["a"] != nil)
        // ...saving changes what ssh connects to, so it goes.
        try await model.store.save()
        #expect(model.connectionTests.results.isEmpty)

        await model.connectionTests.test("a", using: model.commandBuilder)
        #expect(model.connectionTests.results["a"] != nil)
        try tmp.file(".ssh/config", "Host a\n  HostName 10.0.0.3\n")
        model.store.discardChanges()
        #expect(model.connectionTests.results.isEmpty)
    }

    @Test func connectionResultsAreClearedAfterSwitchingFiles() async throws {
        let tmp = try TempDir()
        try tmp.file("other/config", "Host b\n")
        let model = makeTestModel(tmp, config: "Host a\n")
        let original = model.store
        await model.connectionTests.test("a", using: model.commandBuilder)
        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(model.connectionTests.results.isEmpty)
        // The old store no longer reaches the model.
        await model.connectionTests.test("b", using: model.commandBuilder)
        original.discardChanges()
        #expect(model.connectionTests.results["b"] != nil)
        #expect(model.connectableAliases == ["b"])
    }

    @Test func configPathsWithControlCharactersAreInvalid() {
        #expect(!AppSettings.isValidConfigPath("/tmp/a\nb"))
        #expect(!AppSettings.isValidConfigPath("~/x\u{7F}"))
        #expect(!AppSettings.isValidConfigPath("/tmp/a\tb"))
        #expect(AppSettings.isValidConfigPath("/tmp/with space/config"))
    }

    @Test func knownHostsDefaultsToTheHomeFileAndItsBackupKind() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp)
        #expect(model.knownHosts.fileURL.standardizedFileURL == tmp.url.appending(path: ".ssh/known_hosts").standardizedFileURL)
        #expect(model.knownHosts.backupKind == "known_hosts")
        let other = AppModel.knownHostsBackupKind(for: URL(filePath: "/tmp/other_known_hosts"), home: tmp.url)
        #expect(other.hasPrefix("known_hosts-") && other.count == "known_hosts-".count + 12)
    }

    @Test func switchingKnownHostsPersistsAndReplacesTheStore() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp)
        try tmp.file("other/known_hosts", "a.example.com ssh-ed25519 \(KnownHostsModelTests.ed)\n")
        #expect(model.switchKnownHosts(to: tmp.url.appending(path: "other/known_hosts").path))
        #expect(model.knownHosts.document.entries.count == 1)
        #expect(model.settings.knownHostsPath == tmp.url.appending(path: "other/known_hosts").path)
        #expect(!model.switchKnownHosts(to: "relative/path"))
    }

    @Test func backupCountAlsoAppliesToKnownHosts() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp)
        model.setBackupCount(3)
        #expect(model.knownHosts.backupKeep == 3)
    }

    @Test func uploadKeyRunsSshCopyIdWithTheConfigAndTheAliasAfterDoubleDash() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        try tmp.file("work/config", "Host web\n  HostName 10.0.0.1\n")
        let model = makeTestModel(tmp, launcher: launcher)
        #expect(model.switchConfig(to: tmp.url.appending(path: "work/config").path) == .switched)
        let pub = tmp.url.appending(path: ".ssh/id_ed25519.pub")
        #expect(model.uploadKey(publicKey: pub, alias: "web") == .launched(.terminal))
        let request = try #require(launcher.requests.last)
        #expect(request.program == "/usr/bin/ssh-copy-id")
        #expect(request.sshArguments == ["-i", pub.path, "-F", tmp.url.appending(path: "work/config").path, "--", "web"])
    }

    @Test func uploadKeyRefusesUnsavedAliases() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        #expect(model.uploadKey(publicKey: tmp.url.appending(path: "k.pub"), alias: "other") == .failed(.failed("not in the saved file")))
        #expect(launcher.requests.isEmpty)
        #expect(model.errorMessage == String(localized: "connect.notSaved"))
    }

    @Test func unsavedHostsAreRecognizedButPatternsAndSavedHostsAreNot() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host saved\n  HostName 10.0.0.1\nHost *\n  User me\n")
        let added = try HostCommands.addHost(to: model.store)
        #expect(model.isUnsavedHost(added))
        #expect(!model.isUnsavedHost(.host(alias: "saved", occurrence: 0)))
        #expect(!model.isUnsavedHost(.host(alias: "*", occurrence: 0)))
        #expect(!model.isUnsavedHost(.match(index: 0)))
    }

    @Test func noSaveHintWhileAnExternalChangeIsPending() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host saved\n  HostName 10.0.0.1\n")
        let added = try HostCommands.addHost(to: model.store)
        #expect(model.isUnsavedHost(added))
        try tmp.file(".ssh/config", "Host saved\n  HostName 10.0.0.2\n")
        await #expect(throws: ConfigStoreError.conflict) { try await model.store.save() }
        #expect(model.store.externalChangePending)
        #expect(!model.isUnsavedHost(added))
    }

    @Test func settingAGroupIsAnUnsavedEditOfOneLine() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  User u\nHost db\n")
        model.setGroup(.host(alias: "web", occurrence: 0), to: "Prod")
        #expect(model.store.document.render() == "# group: Prod\nHost web\n  User u\nHost db\n")
        #expect(model.existingGroups == ["Prod"])
        #expect(try tmp.read(".ssh/config") == "Host web\n  User u\nHost db\n")
    }

    @Test func blankGroupNameRemovesTheGroup() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "# group: Prod\nHost web\n")
        model.setGroup(.host(alias: "web", occurrence: 0), to: "   ")
        #expect(model.store.document.render() == "Host web\n")
    }

    @Test func lintIssuesAreReportedForTheDocumentBeingEdited() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  IdentityFile ~/.ssh/missing\nHost web\n")
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)).contains(.missingIdentityFile("~/.ssh/missing")))
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 1)) == [.duplicateAlias(alias: "web", isFirst: false)])
        #expect(model.lintIssueMap().count == 2)
    }

    @Test func lintIgnoresPatternsAndUnknownItems() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host *\n  IdentityFile ~/.ssh/missing\n")
        #expect(model.lintIssues(for: .host(alias: "*", occurrence: 0)).isEmpty)
        #expect(model.lintIssues(for: .match(index: 0)).isEmpty)
    }
}
