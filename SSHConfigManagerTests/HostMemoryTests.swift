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
        let all: Set<String> = ["Web", "web", "db"]
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        memory.toggleFavorite("Web", existing: all)
        #expect(!memory.isFavorite("web"))
        memory.toggleFavorite("web", existing: all)
        #expect(memory.isFavorite("Web") && memory.isFavorite("web"))
        memory.toggleFavorite("Web", existing: all)
        #expect(memory.favorites == ["web"])
        memory.toggleFavorite("db", existing: all)
        #expect(HostMemory(defaults: tmp.defaults, key: "k").favorites == ["web", "db"])
    }

    @Test func staleFavoritesArePrunedAtTheLimit() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        let stale = (0..<HostMemory.maxFavorites).map { "old\($0)" }
        for alias in stale { memory.toggleFavorite(alias, existing: Set(stale)) }
        #expect(memory.favorites.count == HostMemory.maxFavorites)
        #expect(memory.toggleFavorite("new", existing: ["new", "old0"]))
        #expect(memory.favorites == ["old0", "new"])
    }

    @Test func fullFavoritesRefuseButRemovalStillWorks() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        let all = (0..<HostMemory.maxFavorites).map { "h\($0)" }
        let existing = Set(all + ["new"])
        for alias in all { memory.toggleFavorite(alias, existing: existing) }
        #expect(!memory.toggleFavorite("new", existing: existing))
        #expect(memory.favorites == all)
        #expect(memory.toggleFavorite("h3", existing: existing))
        #expect(!memory.favorites.contains("h3"))
    }

    @Test func appModelShowsTheLimitMessageWhenFavoritesAreFull() throws {
        let tmp = try TempDir()
        let aliases = (0..<HostMemory.maxFavorites).map { "h\($0)" }
        let model = makeTestModel(tmp, config: aliases.map { "Host \($0)\n" }.joined() + "Host extra\n")
        for alias in aliases { model.toggleFavorite(alias) }
        #expect(model.errorMessage == nil)
        model.toggleFavorite("extra")
        #expect(model.favoriteAliases.count == HostMemory.maxFavorites)
        #expect(!model.favoriteAliases.contains("extra"))
        #expect(model.errorMessage == String(localized: "favorite.limit \(String(HostMemory.maxFavorites))"))
        #expect(model.errorMessage?.contains("\(HostMemory.maxFavorites)") == true)
    }

    @Test func unsavedEditableHostFavoriteSurvivesPruningAtTheCap() throws {
        let tmp = try TempDir()
        let saved = (0..<HostMemory.maxFavorites).map { "s\($0)" }
        let model = makeTestModel(tmp, config: saved.map { "Host \($0)\n" }.joined())
        let added = try HostCommands.addHost(to: model.store)
        let unsaved = try #require(SidebarBuilder.hostEntry(for: added, in: model.store.document)).alias
        #expect(model.isUnsavedHost(added))
        model.toggleFavorite("stale0")
        model.toggleFavorite("stale1")
        model.toggleFavorite(unsaved)
        for alias in saved.prefix(HostMemory.maxFavorites - 3) { model.toggleFavorite(alias) }
        #expect(model.memory.favorites.count == HostMemory.maxFavorites)
        // Full: the next favorite prunes the two stale ones and succeeds.
        model.toggleFavorite(saved[HostMemory.maxFavorites - 3])
        #expect(model.errorMessage == nil)
        #expect(!model.memory.isFavorite("stale0") && !model.memory.isFavorite("stale1"))
        #expect(model.memory.isFavorite(unsaved))
        // Full again with nothing stale: refused, and the unsaved host's favorite is still there.
        model.toggleFavorite(saved[HostMemory.maxFavorites - 2])
        #expect(model.memory.favorites.count == HostMemory.maxFavorites)
        model.toggleFavorite(saved[HostMemory.maxFavorites - 1])
        #expect(model.errorMessage != nil)
        #expect(!model.memory.isFavorite(saved[HostMemory.maxFavorites - 1]))
        #expect(model.memory.isFavorite(unsaved))
        #expect(model.isUnsavedHost(added))
    }

    @Test func corruptStoredDataIsIgnored() throws {
        let tmp = try TempDir()
        tmp.defaults.set("nonsense", forKey: "a")
        tmp.defaults.set(["favorites": "x", "recents": 5], forKey: "b")
        tmp.defaults.set(["favorites": [1, "", "ok", ["n"], "ok"], "recents": [true, "r", "r", ""]], forKey: "c")
        let a = HostMemory(defaults: tmp.defaults, key: "a")
        #expect(a.favorites.isEmpty && a.recents.isEmpty)
        #expect(tmp.defaults.dictionary(forKey: "a")?["favorites"] as? [String] == [])
        #expect(tmp.defaults.dictionary(forKey: "a")?["recents"] as? [String] == [])
        let b = HostMemory(defaults: tmp.defaults, key: "b")
        #expect(b.favorites.isEmpty && b.recents.isEmpty)
        let c = HostMemory(defaults: tmp.defaults, key: "c")
        #expect(c.favorites == ["ok"] && c.recents == ["r"])
        // the normalized form was saved
        let stored = tmp.defaults.dictionary(forKey: "c")
        #expect(stored?["favorites"] as? [String] == ["ok"])
        #expect(stored?["recents"] as? [String] == ["r"])
    }

    @Test func cleanOrMissingStoredDataIsNotRewritten() throws {
        let tmp = try TempDir()
        _ = HostMemory(defaults: tmp.defaults, key: "fresh")
        #expect(tmp.defaults.object(forKey: "fresh") == nil)
        tmp.defaults.set(["favorites": ["a", "b"]], forKey: "partial")
        let partial = HostMemory(defaults: tmp.defaults, key: "partial")
        #expect(partial.favorites == ["a", "b"] && partial.recents.isEmpty)
        let stored = tmp.defaults.dictionary(forKey: "partial")
        #expect(stored?["recents"] == nil)
    }

    @Test func oversizedStoredListsAreCappedKeepingTheFirst() throws {
        let tmp = try TempDir()
        let favorites = (0..<(HostMemory.maxFavorites + 5)).map { "f\($0)" }
        let recents = (0..<(HostMemory.maxRecents + 3)).map { "r\($0)" }
        tmp.defaults.set(["favorites": favorites, "recents": recents], forKey: "k")
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        #expect(memory.favorites == Array(favorites.prefix(HostMemory.maxFavorites)))
        #expect(memory.recents == Array(recents.prefix(HostMemory.maxRecents)))
    }

    @Test func duplicateStoredEntriesKeepTheFirstExactly() throws {
        let tmp = try TempDir()
        tmp.defaults.set(["favorites": ["b", "Web", "b", "web", "Web"], "recents": ["x", "X", "x"]], forKey: "k")
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        #expect(memory.favorites == ["b", "Web", "web"])
        #expect(memory.recents == ["x", "X"])
    }

    @Test func recentsKeepTheTypedSpelling() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        memory.recordConnection("MixedCase.Host")
        #expect(HostMemory(defaults: tmp.defaults, key: "k").recents == ["MixedCase.Host"])
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

    @Test func fellBackConnectsAreRecordedAndKeyUploadsAreNot() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\nHost db\n", isTerminalInstalled: { $0 == .terminal })
        model.settings.setTerminal(.ghostty)
        #expect(model.connect(alias: "web") == .fellBack(from: .ghostty))
        #expect(model.recentAliases == ["web"])
        model.uploadKey(publicKey: tmp.url.appending(path: "k.pub"), alias: "db")
        #expect(model.recentAliases == ["web"])
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
