import Foundation
import Observation
import SSHConfigKit

/// Connection test results for the session (never written to disk).
@MainActor
@Observable
final class ConnectionTestsModel {
    private(set) var results: [String: ConnectionTestResult] = [:]

    /// Forgets one alias's last result (e.g. after its known_hosts entry was deleted).
    func dropResult(for alias: String) {
        results.removeValue(forKey: alias)
    }
    private(set) var running: Set<String> = []
    private(set) var isTestingAll = false

    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var allTask: Task<Void, Never>?
    @ObservationIgnored private var currentRun: UUID?
    @ObservationIgnored private var runAliases: Set<String> = []
    /// Owner token of each in-flight single test; a test whose token was dropped (cancelAll, clear,
    /// or a "test all" that took over its alias) never writes results or touches `running`.
    @ObservationIgnored private var singles: [String: UUID] = [:]

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    /// No-op while `alias` is already being tested (single or as part of "test all").
    func test(_ alias: String, using builder: SSHCommandBuilder) async {
        guard !running.contains(alias) else { return }
        let token = UUID()
        singles[alias] = token
        running.insert(alias)
        let result = await ConnectionTester(commandBuilder: builder, runner: runner).test(alias: alias)
        guard singles[alias] == token else { return }
        singles[alias] = nil
        results[alias] = result
        running.remove(alias)
    }

    /// Tests up to 4 hosts at a time. Starting again cancels the previous run; a stale run never
    /// writes results or clears the new run's state.
    func testAll(_ aliases: [String], using builder: SSHCommandBuilder) {
        stopRun()
        for alias in aliases { singles[alias] = nil }
        let run = UUID()
        currentRun = run
        isTestingAll = true
        runAliases = Set(aliases)
        running.formUnion(aliases)
        let tester = ConnectionTester(commandBuilder: builder, runner: runner)
        allTask = Task { @MainActor [self] in
            await tester.testAll(aliases, maxConcurrent: 4) { alias, result in
                await self.record(alias, result, run: run)
            }
            if currentRun == run { finish() }
        }
    }

    /// Cancels the "test all" run and abandons in-flight single tests (they write nothing).
    func cancelAll() {
        stopRun()
        singles.removeAll()
        running.removeAll()
    }

    private func stopRun() {
        allTask?.cancel()
        allTask = nil
        currentRun = nil
        finish()
    }

    func clear() {
        cancelAll()
        results = [:]
    }

    /// For tests: waits until the current "test all" run (if any) has finished.
    func waitUntilIdle() async {
        await allTask?.value
    }

    private func record(_ alias: String, _ result: ConnectionTestResult, run: UUID) {
        guard currentRun == run else { return }
        results[alias] = result
        running.remove(alias)
    }

    private func finish() {
        isTestingAll = false
        running.subtract(runAliases)
        runAliases = []
    }
}
