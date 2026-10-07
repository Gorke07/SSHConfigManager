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
        let editor = try #require(HostEditorModel(item: a, store: model.store, homeDirectory: tmp.url))
        model.activeEditor = editor
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
}
