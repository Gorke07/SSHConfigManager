import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct QuickConnectModelTests {
    private func model(_ tmp: TempDir, launcher: RecordingLauncher = RecordingLauncher(),
                       openMainWindow: @escaping @MainActor () -> Void = {}) throws -> QuickConnectModel {
        try tmp.file(".ssh/work", "Host vpn\n  HostName vpn.example\nHost web\n")
        let app = makeTestModel(tmp, config: """
        Include work
        Host web
          HostName 10.0.0.1
          User deploy
        Host web
          HostName 10.0.0.2
        Host db db2
          HostName db.İstanbul.example
        Host *.prod
          User ops

        """, launcher: launcher)
        return QuickConnectModel(app: app, openMainWindow: openMainWindow)
    }

    @Test func aliasesDifferingOnlyInCaseAreSeparateEntries() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host Web\n  User upper\nHost web\n  User lower\n  HostName first.example\nHost web\n  HostName second.example\n")
        let quick = QuickConnectModel(app: app, openMainWindow: {})
        #expect(quick.entries.map(\.alias) == ["Web", "web"])
        #expect(quick.entries.last?.subtitle == "lower@first.example")   // first `Host web` block wins
    }

    @Test func entriesAreUniqueConnectableAliases() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        #expect(quick.entries.map(\.alias) == ["web", "db", "vpn"])
        #expect(quick.entries.map(\.isIncluded) == [false, false, true])
        #expect(quick.entries.first?.subtitle == "deploy@10.0.0.1")
    }

    @Test func searchFiltersAndResetsSelection() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        quick.selectedIndex = 2
        quick.query = "istanbul"
        #expect(quick.entries.map(\.alias) == ["db"])
        #expect(quick.selectedEntry?.alias == "db")
        quick.query = "zzz"
        #expect(quick.entries.isEmpty)
        #expect(quick.selectedEntry == nil)
        #expect(!quick.connectSelected())
    }

    @Test func movingWrapsAround() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        quick.move(by: -1)
        #expect(quick.selectedEntry?.alias == "vpn")
        quick.move(by: 1)
        #expect(quick.selectedEntry?.alias == "web")
    }

    @Test func connectingUsesTheSelectedAlias() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let quick = try model(tmp, launcher: launcher)
        quick.move(by: 2)
        #expect(quick.connectSelected())
        await quick.connectTask?.value
        #expect(launcher.requests.first?.sshArguments.last == "vpn")
    }

    @Test func prepareForDisplayClearsQueryAndBumpsFocus() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        quick.query = "x"
        quick.selectedIndex = 1
        let token = quick.focusToken
        quick.prepareForDisplay()
        #expect(quick.query.isEmpty && quick.selectedIndex == 0)
        #expect(quick.focusToken != token)
    }

    @Test func failedLaunchOpensTheMainWindow() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        launcher.error = .automationDenied
        var opened = 0
        let quick = try model(tmp, launcher: launcher, openMainWindow: { opened += 1 })
        #expect(quick.connectSelected())
        await quick.connectTask?.value
        #expect(opened == 1)
        #expect(quick.app.automationDenied)
    }

    @Test func successfulLaunchKeepsTheMainWindowClosed() async throws {
        let tmp = try TempDir()
        var opened = 0
        let quick = try model(tmp, openMainWindow: { opened += 1 })
        #expect(quick.connectSelected())
        await quick.connectTask?.value
        #expect(quick.connectSelected())
        await quick.connectTask?.value
        #expect(opened == 0)
    }

    @Test func emptyQueryShowsFavoritesThenRecentsThenTheRest() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\nHost b\nHost c\nHost d\n")
        app.toggleFavorite("c")
        _ = await app.connect(alias: "b")
        _ = await app.connect(alias: "c")
        let model = QuickConnectModel(app: app)
        #expect(model.entries.map(\.alias) == ["c", "b", "a", "d"])
        #expect(model.entries.map(\.section) == [.favorites, .recents, .all, .all])
        #expect(model.entries.first?.isFavorite == true)
    }

    @Test func searchRanksAndHighlights() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host db-prod\n  HostName 10.0.0.9\nHost prod-web-01\nHost prod\n")
        let model = QuickConnectModel(app: app)
        model.query = "prod"
        #expect(model.entries.map(\.alias) == ["prod", "prod-web-01", "db-prod"])
        #expect(model.entries.allSatisfy { $0.section == nil })
        model.query = "prd web"
        #expect(model.entries.map(\.alias) == ["prod-web-01"])
        #expect(model.entries.first?.aliasOffsets == [0, 1, 3, 5, 6, 7])
        model.query = "10.0.0"
        #expect(model.entries.map(\.alias) == ["db-prod"])
    }

    @Test func groupsAppearOnEntries() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "# group: Prod\nHost web\n")
        #expect(QuickConnectModel(app: app).entries.first?.group == "Prod")
    }

    @Test func copyAndFavoriteActOnTheSelection() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n")
        var copied: [String] = []
        let model = QuickConnectModel(app: app, copyToPasteboard: { copied.append($0) })
        #expect(model.copySelectedCommand())
        #expect(copied == ["ssh -- web"])
        model.toggleFavoriteSelected()
        #expect(app.favoriteAliases == ["web"])
    }

    @Test func previewUsesSshGOutput() async throws {
        let tmp = try TempDir()
        let runner = FixedRunner(result: ProcessResult(exitCode: 0, stdout: "user ubuntu\nhostname 10.0.1.12\nport 2222\nproxyjump bastion\n", stderr: "", timedOut: false))
        let app = makeTestModel(tmp, config: "Host web\n", runner: runner)
        let model = QuickConnectModel(app: app)
        let entry = try #require(model.selectedEntry)
        #expect(model.previewText(for: entry) == "…")
        await app.effectiveConfig.load("web", using: app.commandBuilder)
        #expect(model.previewText(for: entry) == "ubuntu@10.0.1.12:2222 · " + String(localized: "quick.preview.via \("bastion")"))
    }

    @Test func aFailedPreviewIsNotShownAsLoading() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n", runner: FixedRunner.invalid("Bad configuration option: x"))
        let model = QuickConnectModel(app: app)
        let entry = try #require(model.selectedEntry)
        await app.effectiveConfig.load("web", using: app.commandBuilder)
        #expect(model.previewText(for: entry) == nil)
    }

    @Test func whileLoadingThePreviewShowsTheSavedHostName() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n  HostName 10.0.0.5\nHost bare\n")
        let model = QuickConnectModel(app: app)
        let web = try #require(model.entries.first { $0.alias == "web" })
        let bare = try #require(model.entries.first { $0.alias == "bare" })
        #expect(model.previewText(for: web) == "10.0.0.5")
        #expect(model.previewText(for: bare) == "…")
    }

    @Test func duplicateAliasesAppearOnceWhileSearching() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n  User a\nHost web\n  User b\nHost db\n")
        let model = QuickConnectModel(app: app)
        model.query = "web"
        #expect(model.entries.map(\.alias) == ["web"])
        model.query = ""
        #expect(model.entries.map(\.alias).sorted() == ["db", "web"])
    }

    @Test func togglingFavoriteKeepsTheSelectionOnTheSameHost() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\nHost b\nHost c\nHost d\n")
        app.toggleFavorite("c")
        _ = await app.connect(alias: "b")
        let model = QuickConnectModel(app: app)
        model.query = ""
        #expect(model.entries.map(\.alias) == ["c", "b", "a", "d"])
        model.selectedIndex = 3
        model.toggleFavoriteSelected()
        #expect(model.selectedEntry?.alias == "d")
        #expect(app.favoriteAliases.contains("d"))
        model.toggleFavoriteSelected()
        #expect(model.selectedEntry?.alias == "d")
        #expect(!app.favoriteAliases.contains("d"))
    }

    @Test func copyWithNoMatchingEntryReportsFalse() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n")
        var copied: [String] = []
        let model = QuickConnectModel(app: app, copyToPasteboard: { copied.append($0) })
        model.query = "zzz"
        #expect(!model.copySelectedCommand())
        #expect(copied.isEmpty)
    }

    private func storage(_ entries: [QuickConnectEntry]) -> UnsafeRawPointer? {
        entries.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    /// The list is computed once per query and saved-hosts state: the view, the arrow keys and the preview reuse it.
    @Test func entriesAreReusedUntilTheQueryChanges() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\nHost b\nHost c\n")
        let model = QuickConnectModel(app: app)
        let first = model.entries
        model.move(by: 1)
        #expect(storage(model.entries) == storage(first))
        model.query = "b"
        #expect(model.entries.map(\.alias) == ["b"])
        let searched = model.entries
        model.select(searched[0])
        #expect(storage(model.entries) == storage(searched))
        model.query = ""
        #expect(model.entries.map(\.alias) == ["a", "b", "c"])
    }

    @Test func cachedEntriesFollowFavoritesRecentsAndTheSavedFile() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\nHost b\nHost c\n")
        let model = QuickConnectModel(app: app)
        #expect(model.entries.map(\.alias) == ["a", "b", "c"])
        app.toggleFavorite("c")
        #expect(model.entries.map(\.alias) == ["c", "a", "b"])
        #expect(model.entries.first?.isFavorite == true)
        _ = await app.connect(alias: "b")
        #expect(model.entries.map(\.alias) == ["c", "b", "a"])
        model.query = "a"
        #expect(model.entries.map(\.alias) == ["a"])
        try tmp.file(".ssh/config", "Host a\nHost b\nHost c\nHost alpha\n")
        app.store.load()   // the saved file changed on disk
        #expect(model.entries.map(\.alias) == ["a", "alpha"])
        model.query = ""
        #expect(model.entries.map(\.alias) == ["c", "b", "a", "alpha"])
    }
}
