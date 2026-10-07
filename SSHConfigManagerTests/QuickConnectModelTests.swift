import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct QuickConnectModelTests {
    private func model(_ tmp: TempDir, launcher: RecordingLauncher = RecordingLauncher()) throws -> QuickConnectModel {
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
        return QuickConnectModel(app: app)
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
}
