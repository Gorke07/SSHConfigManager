import Foundation
import Synchronization
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
@Suite(.timeLimit(.minutes(1)))
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

    @Test(.timeLimit(.minutes(1))) func cancelLeavesNoFakeResults() async {
        let runner = AliasGatedRunner(result: refused)
        let model = ConnectionTestsModel(runner: runner)
        model.testAll(["a", "b"], using: builder)
        await runner.waitForEntry(of: "a")
        await runner.waitForEntry(of: "b")
        model.cancelAll()
        runner.openAll()   // the cancelled runs now finish with an answer that must be ignored
        await model.waitUntilIdle()
        #expect(model.results.isEmpty)
        #expect(!model.isTestingAll)
        #expect(model.running.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func restartingDoesNotLetTheOldRunClobberTheNewOne() async {
        let runner = AliasGatedRunner(result: refused)
        let model = ConnectionTestsModel(runner: runner)
        model.testAll(["old"], using: builder)
        model.testAll(["new"], using: builder)
        await runner.waitForEntry(of: "new")
        #expect(model.isTestingAll)
        #expect(model.running == ["new"])
        runner.openAll()
        await model.waitUntilIdle()
        #expect(model.results["old"] == nil)
        #expect(model.results["new"]?.status == .connectionRefused)
        #expect(!model.isTestingAll)
    }

    @Test(.timeLimit(.minutes(1))) func clearDuringSingleTestDropsItsResult() async {
        let runner = AliasGatedRunner(result: refused)
        let model = ConnectionTestsModel(runner: runner)
        let single = Task { await model.test("web", using: builder) }
        await runner.waitForEntry(of: "web")
        #expect(model.running == ["web"])
        model.clear()
        #expect(model.running.isEmpty)
        runner.openAll()
        await single.value
        #expect(model.results.isEmpty)
        #expect(model.running.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func singleTestWhileRunningIsANoOp() async {
        let runner = AliasGatedRunner(result: refused)
        let model = ConnectionTestsModel(runner: runner)
        let first = Task { await model.test("web", using: builder) }
        await runner.waitForEntry(of: "web")
        await model.test("web", using: builder)   // returns at once: already running
        runner.openAll()
        await first.value
        #expect(runner.runs == 1)
        #expect(model.results["web"]?.status == .connectionRefused)
        #expect(model.running.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func singleTestCannotRemoveATestAllEntry() async {
        let runner = AliasGatedRunner(result: refused)
        let model = ConnectionTestsModel(runner: runner)
        let single = Task { await model.test("web", using: builder) }
        await runner.waitForEntry(of: "web")
        model.testAll(["web", "db"], using: builder)
        await runner.waitForEntry(of: "db")
        runner.release(alias: "web")   // the oldest "web" run is the single test's: only it finishes
        await single.value
        #expect(model.running == ["web", "db"])
        runner.openAll()
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

    @Test func theTestingStyleHasASymbolAndATitle() {
        let style = ConnectionStatusStyle.testing
        #expect(style.symbol == "ellipsis.circle")
        #expect(style.title == String(localized: "status.testing"))
        #expect(!style.title.isEmpty && !style.title.hasPrefix("status."))
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

/// Suspends each run (identified by the alias after `--`) until it is released, and signals every entry.
final class AliasGatedRunner: ProcessRunning, @unchecked Sendable {
    private struct State {
        var runs = 0
        var isOpen = false
        var seen = Set<String>()   // aliases whose entry the test has already consumed
        var pending: [(alias: String, gate: CheckedContinuation<Void, Never>)] = []
    }
    private let state = Mutex(State())
    private let entries: AsyncStream<String>
    private let entered: AsyncStream<String>.Continuation
    let result: ProcessResult
    var runs: Int { state.withLock { $0.runs } }

    init(result: ProcessResult) {
        self.result = result
        (entries, entered) = AsyncStream.makeStream()
    }

    /// Suspends until a run for `alias` has started (entries of other aliases are skipped).
    /// Tests using it carry `.timeLimit`.
    func waitForEntry(of alias: String) async {
        if state.withLock({ $0.seen.contains(alias) }) { return }
        for await name in entries {
            state.withLock { $0.seen.insert(name) }
            if name == alias { return }
        }
    }

    /// Lets the oldest pending run of `alias` finish.
    func release(alias: String) {
        let gate = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard let index = state.pending.firstIndex(where: { $0.alias == alias }) else { return nil }
            return state.pending.remove(at: index).gate
        }
        gate?.resume()
    }

    /// Releases every pending run and lets later ones through.
    func openAll() {
        let gates = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            defer { state.pending = [] }
            return state.pending.map(\.gate)
        }
        for gate in gates { gate.resume() }
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        let alias = arguments.drop { $0 != "--" }.dropFirst().first ?? ""
        state.withLock { $0.runs += 1 }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pass = state.withLock { state -> Bool in
                if state.isOpen { return true }
                state.pending.append((alias, continuation))   // registered before the entry is announced
                return false
            }
            entered.yield(alias)
            if pass { continuation.resume() }
        }
        return result
    }
}
