import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostMemoryTests {
    @Test func recentsAreMostRecentFirstUniqueAndCapped() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "hostMemory.config")
        for alias in ["a", "b", "c", "d", "e", "f", "b", "B"] { memory.recordConnection(alias) }
        #expect(memory.recents == ["B", "b", "f", "e", "d"])
        let reloaded = HostMemory(defaults: tmp.defaults, key: "hostMemory.config")
        #expect(reloaded.recents == memory.recents)
    }

    @Test func favoritesAreExactAndPersist() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        memory.toggleFavorite("Web")
        #expect(!memory.isFavorite("web"))
        memory.toggleFavorite("web")
        #expect(memory.isFavorite("Web") && memory.isFavorite("web"))
        memory.toggleFavorite("Web")
        #expect(memory.favorites == ["web"])
        memory.toggleFavorite("db")
        #expect(HostMemory(defaults: tmp.defaults, key: "k").favorites == ["web", "db"])
    }

    @Test func caseDifferingAliasesAreSeparateHostsForFavoritesAndRecents() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host Web\n  User upper\nHost web\n  User lower\n")
        #expect(model.savedConnectableHosts.map(\.entry.alias) == ["Web", "web"])
        #expect(model.savedAlias("Web") == "Web")
        #expect(model.savedAlias("web") == "web")
        #expect(model.savedAlias("WEB") == nil)
        model.toggleFavorite("web")
        #expect(model.favoriteAliases == ["web"])
        #expect(!model.memory.isFavorite("Web"))
        model.connect(alias: "Web")
        model.connect(alias: "web")
        #expect(model.recentAliases == ["web", "Web"])
    }

    @Test func appModelRecordsSuccessfulConnectsAndHidesUnsavedOrRemovedHosts() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\nHost db\n")
        model.connect(alias: "web")
        model.toggleFavorite("db")
        model.memory.recordConnection("gone")           // e.g. removed from the file later
        #expect(model.recentAliases == ["web"])
        #expect(model.favoriteAliases == ["db"])
    }

    @Test func failedConnectsAreNotRecorded() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        launcher.error = .failed("x")
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        model.connect(alias: "web")
        #expect(model.recentAliases.isEmpty)
    }

    @Test func eachConfigFileHasItsOwnMemory() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        model.toggleFavorite("web")
        try tmp.file("other/config", "Host web\n")
        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(model.favoriteAliases.isEmpty)
    }
}
