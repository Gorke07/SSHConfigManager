import AppKit
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

    @Test func appearanceDefaultsToSystemAndPersists() throws {
        let tmp = try TempDir()
        #expect(AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).appearance == .system)
        AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).setAppearance(.dark)
        #expect(AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).appearance == .dark)
        tmp.defaults.set("sepia", forKey: "appearance")   // unknown value from a newer or older build
        #expect(AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).appearance == .system)
    }

    @Test func dockIconIsShownByDefaultAndTheChoicePersists() throws {
        let tmp = try TempDir()
        #expect(AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).showsInDock)
        AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).setShowsInDock(false)
        #expect(!AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).showsInDock)
    }

    @Test func darkBackgroundIsASoftBlackAndLightKeepsTheSystemColor() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        var components: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)
        dark.performAsCurrentDrawingAppearance {
            let color = NSColor.appBackground.usingColorSpace(.sRGB)!
            components = (color.redComponent, color.greenComponent, color.blueComponent)
        }
        // Lighter than pure black, still dark, and a touch cool (blue above red).
        #expect(components.r > 0.1 && components.r < 0.16)
        #expect(components.b > components.r)
        let light = try #require(NSAppearance(named: .aqua))
        light.performAsCurrentDrawingAppearance {
            #expect(NSColor.appBackground.usingColorSpace(.sRGB) == NSColor.windowBackgroundColor.usingColorSpace(.sRGB))
        }
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

    @Test func reloadFromDiskRebuildsTheEditorWithoutAView() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n  User old\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        let first = try #require(model.editor(for: a))
        // Main window closed (no view observes diskText); the file changes and the store reloads.
        _ = try tmp.file(".ssh/config", "Host a\n  User new\n")
        model.store.load()
        let reopened = try #require(model.editor(for: a))
        #expect(reopened !== first)
        #expect(reopened.fields["User"] == "new")
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

    @Test func uploadKeyRunsSshCopyIdWithTheConfigAndTheAliasAfterDoubleDash() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        try tmp.file("work/config", "Host web\n  HostName 10.0.0.1\n")
        let model = makeTestModel(tmp, launcher: launcher)
        #expect(model.switchConfig(to: tmp.url.appending(path: "work/config").path) == .switched)
        let pub = tmp.url.appending(path: ".ssh/id_ed25519.pub")
        #expect(await model.uploadKey(publicKey: pub, alias: "web") == .launched(.terminal))
        let request = try #require(launcher.requests.last)
        #expect(request.program == "/usr/bin/ssh-copy-id")
        #expect(request.sshArguments == ["-i", pub.path, "-F", tmp.url.appending(path: "work/config").path, "--", "web"])
    }

    @Test func uploadKeyRefusesUnsavedAliases() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        #expect(await model.uploadKey(publicKey: tmp.url.appending(path: "k.pub"), alias: "other") == .failed(.notSaved))
        #expect(launcher.requests.isEmpty)
        #expect(model.errorMessage == nil)   // the Keys window reports it, not the main window
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

    @Test func renamingASavedHostMakesItUnsaved() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host saved\n  HostName 10.0.0.1\n")
        #expect(!model.isUnsavedHost(.host(alias: "saved", occurrence: 0)))
        try model.store.apply { try $0.updateHost(at: 0, to: HostDraft(patterns: ["renamed"], directives: [DraftDirective(key: "HostName", value: "10.0.0.1")])) }
        #expect(model.isUnsavedHost(.host(alias: "renamed", occurrence: 0)))
    }

    @Test func aLetterCaseVariantOfASavedAliasIsUnsaved() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  HostName 10.0.0.1\n")
        try model.store.apply { try $0.updateHost(at: 0, to: HostDraft(patterns: ["Web"], directives: [DraftDirective(key: "HostName", value: "10.0.0.1")])) }
        #expect(model.isUnsavedHost(.host(alias: "Web", occurrence: 0)))   // alias identity is exact, like ssh's matching
    }

    @Test func includedHostsAreNeverUnsaved() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/config.d/work", "Host vpn\n  HostName vpn.example\n")
        let model = makeTestModel(tmp, config: "Include config.d/*\nHost saved\n")
        let included = try #require(model.store.includedHosts.first)
        #expect(!model.isUnsavedHost(.included(id: included.id)))
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

    @Test func patternsGetTheIdentityFileCheckOnly() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host *\n  IdentityFile ~/.ssh/missing\nHost *\nHost a *\n")
        #expect(model.lintIssues(for: .host(alias: "*", occurrence: 0)) == [.missingIdentityFile("~/.ssh/missing")])
        #expect(model.lintIssues(for: .host(alias: "*", occurrence: 1)).isEmpty)
        #expect(model.lintIssues(for: .host(alias: "a", occurrence: 0)).isEmpty)
        #expect(model.lintIssues(for: .match(index: 0)).isEmpty)
    }

    @Test func anIncludeBeforeTheRootBlockMakesItALaterDuplicate() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/extra.conf", "Host web\n  User x\n")
        let model = makeTestModel(tmp, config: "Include extra.conf\nHost web\n  User me\n")
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: false)])
    }

    @Test func anIncludeDefiningOnlyACaseVariantIsCaseOnlyNotLater() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/extra.conf", "Host Web\n  User x\n")
        let model = makeTestModel(tmp, config: "Include extra.conf\nHost web\n  User me\n")
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAliasCaseOnly(alias: "web")])
    }

    @Test func caseVariantRootBlocksAreCaseOnlyForBoth() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\nHost Web\n")
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAliasCaseOnly(alias: "web")])
        #expect(model.lintIssues(for: .host(alias: "Web", occurrence: 0)) == [.duplicateAliasCaseOnly(alias: "Web")])
    }

    @Test func anIncludeAfterTheRootBlockKeepsItFirst() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/extra.conf", "Host web\n  User x\n")
        let model = makeTestModel(tmp, config: "Host web\n  User me\nInclude extra.conf\n")
        // Include after a Host block belongs to that block's scope; the root block is still first.
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: true)])
    }

    @Test func groupNamesDifferingOnlyInCaseHaveAStableOrder() throws {
        let tmp = try TempDir()
        let a = makeTestModel(tmp, config: "# group: prod\nHost a\n# group: Prod\nHost b\n")
        let b = makeTestModel(tmp, config: "# group: Prod\nHost a\n# group: prod\nHost b\n")
        #expect(a.existingGroups == b.existingGroups)
    }

    @Test func effectiveSettingsStateIsSessionState() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        #expect(!model.effectiveSettingsExpanded && !model.effectiveSettingsShowAll)
        model.effectiveSettingsExpanded = true
        model.select(.host(alias: "a", occurrence: 0))
        #expect(model.effectiveSettingsExpanded)
    }

    // MARK: Task 6

    @Test func anUnappliedGroupDraftIsAPendingEdit() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "# group: prod\nHost a\nHost b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        let b = SidebarItem.host(alias: "b", occurrence: 0)
        model.select(a)
        #expect(!model.hasPendingFormEdits)
        model.groupDraft = "  prod "
        #expect(!model.hasPendingFormEdits)
        model.groupDraft = "staging"
        #expect(model.hasPendingFormEdits)

        model.requestSelect(b)
        #expect(model.pendingSelection == b)
        #expect(model.selection == a)

        model.confirmPendingSelection()
        #expect(model.selection == b)
        #expect(model.groupDraft == nil)
        #expect(!model.hasPendingFormEdits)
        #expect(model.savedGroup(for: a) == "prod")
    }

    @Test func applyingOrReloadingResetsTheGroupDraft() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        model.groupDraft = "x"
        model.setGroup(a, to: "x")
        #expect(model.groupDraft == nil)
        #expect(model.savedGroup(for: a) == "x")
        #expect(!model.hasPendingFormEdits)

        model.groupDraft = "y"
        #expect(model.hasPendingFormEdits)
        model.store.load()
        #expect(model.groupDraft == nil)
        #expect(!model.hasPendingFormEdits)
    }

    @Test func lintMapIsReusedUntilTheDocumentChanges() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/id_a", "x")
        let model = makeTestModel(tmp, config: "Host a\n  IdentityFile ~/.ssh/id_a\nHost b\n")
        let reads = ReadCounter()
        model.keyEncryptionReader = { _ in reads.hit(); return .unknown }
        _ = model.lintIssueMap()
        _ = model.lintIssues(for: .host(alias: "a", occurrence: 0))
        _ = model.lintIssueMap()
        #expect(reads.count == 1)
        model.setGroup(.host(alias: "b", occurrence: 0), to: "g")
        _ = model.lintIssueMap()
        #expect(reads.count == 2)
    }

    @Test func deletingAnEarlierOccurrenceMovesALaterSelection() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  User a\nHost web\n  User b\nHost web\n  User c\nHost other\n")
        let w = { SidebarItem.host(alias: "web", occurrence: $0) }
        model.select(w(2))
        let editor = try #require(model.editor(for: w(2)))
        model.requestDelete(w(0))
        model.confirmPendingDelete()
        #expect(model.selection == w(1))
        #expect(editor.item == w(1))
        #expect(model.activeEditor === editor)

        // An earlier occurrence than the selection is unaffected by a later delete; other aliases too.
        model.requestDelete(SidebarItem.host(alias: "other", occurrence: 0))
        model.confirmPendingDelete()
        #expect(model.selection == w(1))

        model.requestDelete(w(1))
        model.confirmPendingDelete()
        #expect(model.selection == nil)
    }

    @Test func deletingALaterOccurrenceKeepsTheSelection() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\nHost web\nHost web\n")
        let w = { SidebarItem.host(alias: "web", occurrence: $0) }
        model.select(w(0))
        model.requestDelete(w(2))
        model.confirmPendingDelete()
        #expect(model.selection == w(0))
    }

    @Test func aTopLevelIncludeDefiningTheAliasMakesTheRootBlockLater() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/one.conf", "Host other\n")
        _ = try tmp.file(".ssh/two.conf", "Host web\n")
        let model = makeTestModel(tmp, config: "Include one.conf\nHost web\nInclude two.conf\n")
        // one.conf does not define web, two.conf comes after the block: the root block is first.
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: true)])

        let later = makeTestModel(tmp, config: "Include one.conf\nInclude two.conf\nHost web\n")
        #expect(later.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: false)])
    }

    @Test func anIncludeInANonMatchingHostBlockIsIgnored() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/two.conf", "Host web\n")
        let ignored = makeTestModel(tmp, config: "Host other\n  Include two.conf\nHost web\n")
        #expect(ignored.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: true)])

        let matching = makeTestModel(tmp, config: "Host w*\n  Include two.conf\nHost web\n")
        #expect(matching.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: false)])
    }
    @Test func deletingAnEarlierPatternOrGroupedBlockMovesTheSelection() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host *\n  User a\n# group: g\nHost *\n  User b\nHost *\n  User c\n")
        let star = { SidebarItem.host(alias: "*", occurrence: $0) }
        model.select(star(2))
        model.requestDelete(star(1))   // block with a "# group:" line above it
        model.confirmPendingDelete()
        #expect(model.selection == star(1))
        model.requestDelete(star(0))
        model.confirmPendingDelete()
        #expect(model.selection == star(0))
        #expect(model.store.document.hosts.count == 1)
    }

    @Test func unencryptedKeysAreRowHintsNotHostWarnings() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/id_a", "x")
        let model = makeTestModel(tmp, config: "Host a\n  IdentityFile ~/.ssh/id_a\n  IdentityFile ~/.ssh/missing\n")
        model.keyEncryptionReader = { _ in .unencrypted }
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        #expect(model.unencryptedIdentityFiles(for: a) == ["~/.ssh/id_a"])
        #expect(model.lintIssues(for: a).filter(\.isHostWarning) == [.missingIdentityFile("~/.ssh/missing")])
    }

    @Test func invalidateLintForcesAFreshRead() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n  IdentityFile ~/.ssh/id_a\n")
        let reads = ReadCounter()
        model.keyEncryptionReader = { _ in reads.hit(); return .unencrypted }
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        #expect(model.lintIssues(for: a) == [.missingIdentityFile("~/.ssh/id_a")])
        _ = try tmp.file(".ssh/id_a", "x")
        #expect(model.lintIssues(for: a) == [.missingIdentityFile("~/.ssh/id_a")])   // memoized
        let revision = model.lintRevision
        model.invalidateLint()
        #expect(model.lintRevision != revision)
        #expect(model.lintIssues(for: a) == [.unencryptedKey("~/.ssh/id_a")])
        #expect(reads.count == 1)
        // The key file did not change since the last lint pass: activation leaves the lint alone.
        model.refreshIncludes()
        #expect(model.lintRevision == revision + 1)
    }

    @Test func activationInvalidatesTheLintOnlyWhenAKeyFileOrAnIncludeChanged() throws {
        let tmp = try TempDir()
        let key = try tmp.file(".ssh/id_a", "x")
        let model = makeTestModel(tmp, config: "Host a\n  IdentityFile ~/.ssh/id_a\n  IdentityFile ~/.ssh/id_later\n")
        model.keyEncryptionReader = { _ in .unknown }
        _ = model.lintIssueMap()
        let revision = model.lintRevision

        model.refreshIncludes()
        #expect(model.lintRevision == revision)

        try "xyz".write(to: key, atomically: false, encoding: .utf8)   // size changes
        model.refreshIncludes()
        #expect(model.lintRevision == revision + 1)

        _ = model.lintIssueMap()
        model.refreshIncludes()
        #expect(model.lintRevision == revision + 1)

        _ = try tmp.file(".ssh/id_later", "y")                          // a missing key appears
        model.refreshIncludes()
        #expect(model.lintRevision == revision + 2)

        _ = model.lintIssueMap()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: key.path)
        model.refreshIncludes()
        #expect(model.lintRevision == revision + 3)                       // mtime alone changes
    }

    @Test func includesNamingEachOtherTerminateWithTheRightWording() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/a.conf", "Include ~/.ssh/*.conf\nHost web\n")
        _ = try tmp.file(".ssh/b.conf", "Include ~/.ssh/*.conf\n")
        _ = try tmp.file(".ssh/c.conf", "Include ~/.ssh/*.conf\n")
        let model = makeTestModel(tmp, config: "Include a.conf b.conf c.conf\nHost web\n")
        let start = Date()
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: false)])
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func anIncludeInMatchAllCountsButOtherMatchCriteriaAreIgnored() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/two.conf", "Host web\n")
        let all = makeTestModel(tmp, config: "Match all\n  Include two.conf\nHost web\n")
        #expect(all.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: false)])
        let other = makeTestModel(tmp, config: "Match host nomatch\n  Include two.conf\nHost web\n")
        #expect(other.lintIssues(for: .host(alias: "web", occurrence: 0)) == [.duplicateAlias(alias: "web", isFirst: true)])
    }

    @Test func aGroupDraftIsAppliedBeforeSavingAndIsNotABlockedFormEdit() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        model.groupDraft = "prod"
        #expect(model.hasPendingFormEdits)
        #expect(model.hasPendingGroupDraft)
        #expect(!model.hasBlockedFormEdits)
        model.applyPendingGroupDraft()
        #expect(model.savedGroup(for: a) == "prod")
        #expect(model.store.hasUnsavedChanges)
        #expect(model.groupDraft == nil)
        #expect(!model.hasPendingFormEdits)
    }

    @Test func aGroupDraftSurvivesSaveNoticesButNotAReload() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        model.setGroup(.host(alias: "b", occurrence: 0), to: "x")
        model.groupDraft = "draft"
        try await model.store.save()   // a save notice, not a reload
        #expect(model.groupDraft == "draft")
        model.store.load()
        #expect(model.groupDraft == nil)
    }

    @Test func aGroupDraftThatCannotBeAppliedStaysPendingWithAnError() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        model.groupDraft = "bad\u{1B}group"
        model.applyPendingGroupDraft()
        #expect(model.errorMessage != nil)
        #expect(model.hasPendingGroupDraft)
        #expect(!model.hasBlockedFormEdits)
        #expect(!model.store.hasUnsavedChanges)
    }

    @Test func aGroupDraftForAHostThatIsGoneIsDropped() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        model.select(a)
        model.groupDraft = "x"
        try model.store.apply { try $0.removeHost(at: SidebarBuilder.hostEntry(for: a, in: $0)!.headerLine) }
        #expect(!model.hasPendingGroupDraft)
        #expect(!model.hasPendingFormEdits)
        model.applyPendingGroupDraft()
        #expect(model.groupDraft == nil)
    }

    // MARK: Add/Duplicate with pending form edits (2A-8), Save before switching (2A-5)

    private func blockedEditor(_ model: AppModel, _ item: SidebarItem) throws {
        model.select(item)
        let editor = try #require(model.editor(for: item))
        editor.fields["Port"] = "abc"
        #expect(!editor.commit())
        #expect(model.hasPendingFormEdits)
    }

    @Test func addHostWithPendingEditsCreatesNothingUntilConfirmed() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        try blockedEditor(model, a)
        model.addHost()
        #expect(model.pendingCreation == .new)
        #expect(model.hasPendingDiscardConfirmation)
        #expect(model.store.document.hosts.map(\.alias) == ["a"])
        #expect(!model.store.hasUnsavedChanges)

        model.cancelPendingSelection()
        #expect(model.pendingCreation == nil)
        #expect(model.store.document.hosts.map(\.alias) == ["a"])
        #expect(model.selection == a)

        model.addHost()
        model.confirmPendingSelection()
        #expect(model.store.document.hosts.map(\.alias) == ["new-host", "a"] || model.store.document.hosts.map(\.alias) == ["a", "new-host"])
        #expect(model.selection == .host(alias: "new-host", occurrence: 0))
        #expect(!model.hasPendingFormEdits)
    }

    @Test func duplicateHostWithPendingEditsCreatesNothingUntilConfirmed() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n  User u\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        try blockedEditor(model, a)
        model.duplicateHost(a)
        #expect(model.pendingCreation == .duplicate(a))
        #expect(model.store.document.hosts.count == 1)
        model.cancelPendingSelection()
        #expect(model.store.document.hosts.count == 1)
        model.duplicateHost(a)
        model.confirmPendingSelection()
        #expect(model.store.document.hosts.map(\.alias) == ["a", "a-copy"])
        #expect(model.selection == .host(alias: "a-copy", occurrence: 0))
    }

    @Test func addHostWithoutPendingEditsCreatesAtOnce() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        model.addHost()
        #expect(model.pendingCreation == nil)
        #expect(model.store.document.hosts.count == 2)
        #expect(model.selection == .host(alias: "new-host", occurrence: 0))
    }

    @Test func saveThenSwitchWritesBeforeSwitching() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        try model.store.apply { _ = try $0.addHost(HostDraft(patterns: ["new"])) }
        let other = tmp.url.appending(path: "other/config").path
        #expect(model.switchConfig(to: other) == .needsConfirmation)
        #expect(await model.saveThenSwitchConfig(to: other) == .switched)
        #expect(try tmp.read(".ssh/config").contains("Host new"))
        #expect(model.store.fileURL.path.hasSuffix("other/config"))
    }

    @Test func saveThenSwitchRefusesWhileFormEditsAreBlocked() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        try blockedEditor(model, a)
        #expect(!model.store.hasUnsavedChanges)   // only blocked form edits are pending
        let result = await model.saveThenSwitchConfig(to: tmp.url.appending(path: "other/config").path)
        #expect(result == .failed(String(localized: "discardForm.message")))
        #expect(!model.store.fileURL.path.hasSuffix("other/config"))
        #expect(model.hasBlockedFormEdits)
    }

    @Test func switchingConfigClearsPendingConfirmations() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n")
        try tmp.file("other/config", "Host c\n")
        let a = SidebarItem.host(alias: "a", occurrence: 0)
        try blockedEditor(model, a)
        model.requestSelect(.host(alias: "b", occurrence: 0))
        #expect(model.pendingSelection != nil)
        model.addHost()
        #expect(model.pendingCreation == .new)
        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path, discardingUnsavedChanges: true) == .switched)
        #expect(model.pendingSelection == nil)
        #expect(model.pendingCreation == nil)
        #expect(!model.hasPendingDiscardConfirmation)
    }

    @Test func saveThenSwitchStaysWhenTheSaveFails() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n", runner: FixedRunner.invalid("line 2: Bad configuration option: bogus"))
        try tmp.file("other/config", "Host b\n")
        try model.store.apply { _ = try $0.addHost(HostDraft(patterns: ["new"])) }
        let result = await model.saveThenSwitchConfig(to: tmp.url.appending(path: "other/config").path)
        guard case .failed(let message) = result else { Issue.record("failed bekleniyordu"); return }
        #expect(!message.isEmpty)
        #expect(!model.store.fileURL.path.hasSuffix("other/config"))
        #expect(model.store.hasUnsavedChanges)
        #expect(try tmp.read(".ssh/config") == "Host a\n")
    }
}

private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func hit() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
