import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct StatusSummaryTests {
    @Test func categoriesCoverEveryStatus() {
        #expect(StatusCategory.of(.reachable) == .ok)
        #expect(StatusCategory.of(.authenticationRequired) == .attention)
        #expect(StatusCategory.of(.unknownHostKey) == .attention)
        for status in [ConnectionStatus.hostKeyChanged, .timeout, .dnsFailure, .connectionRefused, .other] {
            #expect(StatusCategory.of(status) == .failed)
        }
    }

    @Test func countsOnlyConnectableHostsAndTheFilterNarrowsTheSidebar() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\nHost *\n  User x\n", runner: FixedRunner.invalid("Connection refused"))
        await model.connectionTests.test("a", using: model.commandBuilder)
        #expect(model.statusCounts == [.failed: 1])
        model.statusFilter = .failed
        #expect(model.passesStatusFilter(.host(alias: "a", occurrence: 0)))
        #expect(!model.passesStatusFilter(.host(alias: "b", occurrence: 0)))
        #expect(!model.passesStatusFilter(.host(alias: "*", occurrence: 0)))   // no connectable alias
        try tmp.file(".ssh/config", "Host a\n  Port 2\n")
        model.store.load()                     // saved file changed: results and the filter are cleared
        #expect(model.statusFilter == nil)
        #expect(model.connectionTests.results.isEmpty)
    }

    @Test func switchingConfigClearsTheFilter() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other-config", "Host z\n")
        model.statusFilter = .ok
        #expect(model.switchConfig(to: tmp.url.appending(path: "other-config").path) == .switched)
        #expect(model.statusFilter == nil)
    }

    @Test func deleteGoesThroughAConfirmation() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        model.requestDelete(.host(alias: "a", occurrence: 0))
        #expect(model.pendingDelete == .host(alias: "a", occurrence: 0))
        #expect(model.store.document.hosts.count == 1)
        model.confirmPendingDelete()
        #expect(model.pendingDelete == nil)
        #expect(model.store.document.hosts.isEmpty)
    }

    @Test func requestDeleteIgnoresMissingHosts() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        model.requestDelete(.host(alias: "nope", occurrence: 0))
        #expect(model.pendingDelete == nil)
    }

    @Test func copySSHCommandUsesTheInjectedWriter() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        var copied: [String] = []
        model.copySSHCommand(.host(alias: "a", occurrence: 0)) { copied.append($0) }
        #expect(copied.count == 1)
        #expect(copied[0].contains("ssh"))
        #expect(copied[0].contains("a"))
    }
}
