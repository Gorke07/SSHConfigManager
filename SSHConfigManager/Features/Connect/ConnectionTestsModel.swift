import Foundation
import Observation
import SSHConfigKit

/// Connection test results for the session (never written to disk).
@MainActor
@Observable
final class ConnectionTestsModel {
    private(set) var results: [String: ConnectionTestResult] = [:]
    private(set) var running: Set<String> = []
    private(set) var isTestingAll = false

    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var allTask: Task<Void, Never>?
    @ObservationIgnored private var currentRun: UUID?

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    func test(_ alias: String, using builder: SSHCommandBuilder) async {
        running.insert(alias)
        let result = await ConnectionTester(commandBuilder: builder, runner: runner).test(alias: alias)
        results[alias] = result
        running.remove(alias)
    }

    /// Tests up to 4 hosts at a time. Starting again cancels the previous run; a stale run never
    /// writes results or clears the new run's state.
    func testAll(_ aliases: [String], using builder: SSHCommandBuilder) {
        cancelAll()
        let run = UUID()
        currentRun = run
        isTestingAll = true
        running.formUnion(aliases)
        let tester = ConnectionTester(commandBuilder: builder, runner: runner)
        allTask = Task { @MainActor [self] in
            await tester.testAll(aliases, maxConcurrent: 4) { alias, result in
                await self.record(alias, result, run: run)
            }
            if currentRun == run { finish() }
        }
    }

    func cancelAll() {
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
        running.removeAll()
    }
}
