import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct ConnectionTestsModelTests {
    let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
    let refused = ProcessResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host h port 1: Connection refused\r\n", timedOut: false)

    @Test func singleTestRecordsResult() async {
        let model = ConnectionTestsModel(runner: FixedRunner(result: refused))
        await model.test("web", using: builder)
        #expect(model.results["web"]?.status == .connectionRefused)
        #expect(model.results["web"]?.detail.contains("Connection refused") == true)
        #expect(model.running.isEmpty)
    }

    @Test func testAllRecordsEveryAlias() async {
        let model = ConnectionTestsModel(runner: FixedRunner.valid)
        model.testAll(["a", "b", "c"], using: builder)
        #expect(model.isTestingAll)
        await model.waitUntilIdle()
        #expect(Set(model.results.keys) == ["a", "b", "c"])
        #expect(model.results.values.allSatisfy { $0.status == .reachable })
        #expect(!model.isTestingAll)
        #expect(model.running.isEmpty)
    }

    @Test func cancelLeavesNoFakeResults() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(400), result: refused))
        model.testAll(["a", "b"], using: builder)
        try? await Task.sleep(for: .milliseconds(50))
        model.cancelAll()
        await model.waitUntilIdle()
        #expect(model.results.isEmpty)
        #expect(!model.isTestingAll)
        #expect(model.running.isEmpty)
    }

    @Test func restartingDoesNotLetTheOldRunClobberTheNewOne() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(200), result: refused))
        model.testAll(["old"], using: builder)
        model.testAll(["new"], using: builder)
        await model.waitUntilIdle()
        #expect(model.results["old"] == nil)
        #expect(model.results["new"]?.status == .connectionRefused)
        #expect(!model.isTestingAll)
    }

    @Test func switchingConfigClearsResults() async throws {
        let tmp = try TempDir()
        try tmp.file("other/config", "Host b\n")
        let app = makeTestModel(tmp, config: "Host a\n")
        await app.connectionTests.test("a", using: app.commandBuilder)
        #expect(!app.connectionTests.results.isEmpty)
        #expect(app.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(app.connectionTests.results.isEmpty)
    }

    @Test(arguments: [
        ConnectionStatus.reachable, .authenticationRequired, .hostKeyChanged, .unknownHostKey,
        .timeout, .dnsFailure, .connectionRefused, .other,
    ])
    func everyStatusHasAStyle(status: ConnectionStatus) {
        let style = ConnectionStatusStyle.style(for: status)
        #expect(!style.symbol.isEmpty)
        #expect(!style.title.isEmpty && !style.title.hasPrefix("status."))
    }
}
