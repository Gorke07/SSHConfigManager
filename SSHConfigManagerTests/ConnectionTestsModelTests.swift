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
        try? await Task.sleep(for: .milliseconds(600))
        #expect(model.results.isEmpty)
        #expect(!model.isTestingAll)
        #expect(model.running.isEmpty)
    }

    @Test func restartingDoesNotLetTheOldRunClobberTheNewOne() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(200), result: refused))
        model.testAll(["old"], using: builder)
        model.testAll(["new"], using: builder)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.isTestingAll)
        #expect(model.running == ["new"])
        await model.waitUntilIdle()
        #expect(model.results["old"] == nil)
        #expect(model.results["new"]?.status == .connectionRefused)
        #expect(!model.isTestingAll)
    }

    @Test func clearDuringSingleTestDropsItsResult() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(300), result: refused))
        let single = Task { await model.test("web", using: builder) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.running == ["web"])
        model.clear()
        #expect(model.running.isEmpty)
        await single.value
        #expect(model.results.isEmpty)
        #expect(model.running.isEmpty)
    }

    @Test func singleTestWhileRunningIsANoOp() async {
        let runner = CountingRunner(delay: .milliseconds(300), result: refused)
        let model = ConnectionTestsModel(runner: runner)
        let first = Task { await model.test("web", using: builder) }
        try? await Task.sleep(for: .milliseconds(50))
        await model.test("web", using: builder)
        await first.value
        #expect(runner.count == 1)
        #expect(model.results["web"]?.status == .connectionRefused)
        #expect(model.running.isEmpty)
    }

    @Test func singleTestCannotRemoveATestAllEntry() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(300), result: refused))
        let single = Task { await model.test("web", using: builder) }
        try? await Task.sleep(for: .milliseconds(50))
        model.testAll(["web", "db"], using: builder)
        await single.value
        #expect(model.running == ["web", "db"])
        await model.waitUntilIdle()
        #expect(Set(model.results.keys) == ["web", "db"])
        #expect(model.running.isEmpty)
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

    /// First call for "a" answers fast, later ones slowly; "slow" takes a middle amount.
    private final class StagedRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let result: ProcessResult
        init(result: ProcessResult) { self.result = result }

        func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
            let isSlow = arguments.contains("slow")
            let call = lock.withLock { calls += 1; return calls }
            let delay: Duration = isSlow ? .milliseconds(300) : (call == 1 ? .milliseconds(10) : .milliseconds(900))
            try await Task.sleep(for: delay)
            return result
        }
    }

    @Test func aSingleTestStartedAfterItsAliasWasRecordedKeepsItsSpinnerWhenTestAllEnds() async {
        let model = ConnectionTestsModel(runner: StagedRunner(result: refused))
        model.testAll(["a", "slow"], using: builder)
        while model.results["a"] == nil { try? await Task.sleep(for: .milliseconds(10)) }
        let single = Task { await model.test("a", using: builder) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.running.contains("a"))
        await model.waitUntilIdle()
        #expect(!model.isTestingAll)
        #expect(model.running == ["a"])
        await single.value
        #expect(model.running.isEmpty)
    }
}

/// Counts how many times ssh would have been started.
final class CountingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0
    let delay: Duration
    let result: ProcessResult
    init(delay: Duration, result: ProcessResult) { self.delay = delay; self.result = result }
    var count: Int { lock.withLock { runs } }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        lock.withLock { runs += 1 }
        try await Task.sleep(for: delay)
        return result
    }
}
