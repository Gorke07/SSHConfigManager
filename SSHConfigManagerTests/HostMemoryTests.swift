import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostMemoryTests {
    @Test func recentsAreMostRecentFirstUniqueAndCapped() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "hostMemory.config")
        for alias in ["a", "b", "c", "d", "e", "f", "B"] { memory.recordConnection(alias) }
        #expect(memory.recents == ["B", "f", "e", "d", "c"])
        let reloaded = HostMemory(defaults: tmp.defaults, key: "hostMemory.config")
        #expect(reloaded.recents == memory.recents)
    }

    @Test func favoritesToggleCaseInsensitivelyAndPersist() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        memory.toggleFavorite("Web")
        #expect(memory.isFavorite("web"))
        memory.toggleFavorite("WEB")
        #expect(!memory.isFavorite("web"))
        memory.toggleFavorite("db")
        #expect(HostMemory(defaults: tmp.defaults, key: "k").favorites == ["db"])
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
