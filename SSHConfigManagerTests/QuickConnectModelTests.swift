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

    @Test func connectingUsesTheSelectedAlias() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let quick = try model(tmp, launcher: launcher)
        quick.move(by: 2)
        #expect(quick.connectSelected())
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

    @Test func failedLaunchOpensTheMainWindow() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        launcher.error = .automationDenied
        var opened = 0
        let quick = try model(tmp, launcher: launcher, openMainWindow: { opened += 1 })
        #expect(quick.connectSelected())
        #expect(opened == 1)
        #expect(quick.app.automationDenied)
    }

    @Test func successfulLaunchKeepsTheMainWindowClosed() throws {
        let tmp = try TempDir()
        var opened = 0
        let quick = try model(tmp, openMainWindow: { opened += 1 })
        #expect(quick.connectSelected())
        #expect(opened == 0)
    }

    @Test func emptyQueryShowsFavoritesThenRecentsThenTheRest() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\nHost b\nHost c\nHost d\n")
        app.toggleFavorite("c")
        _ = app.connect(alias: "b")
        _ = app.connect(alias: "c")
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
        model.copySelectedCommand()
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
        #expect(model.previewText(for: entry) == nil)
        #expect(model.isPreviewLoading(for: entry))
        await app.effectiveConfig.load("web", using: app.commandBuilder)
        #expect(!model.isPreviewLoading(for: entry))
        #expect(model.previewText(for: entry) == "ubuntu@10.0.1.12:2222 · " + String(localized: "quick.preview.via \("bastion")"))
    }

    @Test func aFailedPreviewIsNotShownAsLoading() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n", runner: FixedRunner.invalid("Bad configuration option: x"))
        let model = QuickConnectModel(app: app)
        let entry = try #require(model.selectedEntry)
        await app.effectiveConfig.load("web", using: app.commandBuilder)
        #expect(model.previewText(for: entry) == nil)
        #expect(!model.isPreviewLoading(for: entry))
    }
}
