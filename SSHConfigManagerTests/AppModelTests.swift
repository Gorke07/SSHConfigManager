import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct AppModelTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
    }

    @Test func settingsDefaultsAndPersistence() throws {
        let tmp = try TempDir()
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, homeDirectory: tmp.url)
        #expect(settings.configPath == "~/.ssh/config")
        #expect(settings.backupCount == 10)
        #expect(settings.configURL == tmp.url.appending(path: ".ssh/config"))

        settings.setConfigPath("~/dotfiles/ssh/config")
        settings.setBackupCount(99)
        let reloaded = AppSettings(defaults: defaults, homeDirectory: tmp.url)
        #expect(reloaded.configPath == "~/dotfiles/ssh/config")
        #expect(reloaded.backupCount == 50)
    }

    @Test func expandAndDisplayPaths() throws {
        let home = URL(filePath: "/Users/test")
        #expect(AppSettings.expand("~", home: home) == home)
        #expect(AppSettings.expand("~/a/b", home: home) == home.appending(path: "a/b"))
        #expect(AppSettings.expand("/etc/ssh/x", home: home) == URL(filePath: "/etc/ssh/x"))
        let settings = AppSettings(defaults: freshDefaults(), homeDirectory: home)
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
}
