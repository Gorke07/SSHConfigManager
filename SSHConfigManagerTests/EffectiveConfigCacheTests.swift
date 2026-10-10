import Foundation
import Synchronization
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

/// Counts runs and tracks the peak number running at once.
final class PeakRunner: ProcessRunning, @unchecked Sendable {
    let delay: Duration
    let output: String
    private let state = Mutex((running: 0, peak: 0, runs: 0, lastArguments: [String]()))
    var peak: Int { state.withLock { $0.peak } }
    var runs: Int { state.withLock { $0.runs } }
    var lastArguments: [String] { state.withLock { $0.lastArguments } }
    init(delay: Duration, output: String) { self.delay = delay; self.output = output }
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        state.withLock { $0.running += 1; $0.peak = max($0.peak, $0.running); $0.runs += 1; $0.lastArguments = arguments }
        try? await Task.sleep(for: delay)
        state.withLock { $0.running -= 1 }
        return ProcessResult(exitCode: 0, stdout: output, stderr: "", timedOut: false)
    }
}

@MainActor
struct EffectiveConfigCacheTests {
    let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))

    @Test func loadsOnceAndCachesCaseInsensitively() async {
        let runner = PeakRunner(delay: .milliseconds(10), output: "hostname 10.0.0.1\nport 22\n")
        let cache = EffectiveConfigCache(runner: runner)
        await cache.load("web", using: builder)
        await cache.load("WEB", using: builder)
        #expect(runner.runs == 1)
        #expect(cache.options(for: "Web")?.first("hostname") == "10.0.0.1")
        #expect(runner.lastArguments == ["-G", "--", "web"])
    }

    @Test func atMostTwoRunAtOnceAndConcurrentRequestsShareOneRun() async {
        let runner = PeakRunner(delay: .milliseconds(150), output: "hostname h\n")
        let cache = EffectiveConfigCache(runner: runner)
        await withTaskGroup(of: Void.self) { group in
            for alias in ["a", "b", "c", "d", "a"] { group.addTask { await cache.load(alias, using: builder) } }
        }
        #expect(runner.peak <= 2)
        #expect(runner.runs == 4)
    }

    @Test func clearDropsResultsAndLateAnswers() async {
        let runner = PeakRunner(delay: .milliseconds(200), output: "hostname h\n")
        let cache = EffectiveConfigCache(runner: runner)
        let task = Task { await cache.load("a", using: builder) }
        try? await Task.sleep(for: .milliseconds(50))
        cache.clear()
        await task.value
        #expect(cache.options(for: "a") == nil)
    }

    @Test func aWaiterQueuedBeforeClearDoesNotRunSsh() async {
        let runner = PeakRunner(delay: .milliseconds(200), output: "hostname h\n")
        let cache = EffectiveConfigCache(runner: runner)
        let tasks = ["a", "b", "c"].map { alias in Task { await cache.load(alias, using: builder) } }
        try? await Task.sleep(for: .milliseconds(50))
        cache.clear()
        for task in tasks { await task.value }
        #expect(runner.runs == 2)
        #expect(cache.options(for: "c") == nil)
        await cache.load("d", using: builder)
        #expect(runner.runs == 3)
    }

    @Test func aNonZeroExitWithoutStderrIsReportedByItsCode() async {
        let runner = FixedRunner(result: ProcessResult(exitCode: 255, stdout: "", stderr: "", timedOut: false))
        let cache = EffectiveConfigCache(runner: runner)
        await cache.load("a", using: builder)
        #expect(cache.failure(for: "a") == "exit 255")
    }

    @Test func failuresAreKept() async {
        let cache = EffectiveConfigCache(runner: FixedRunner.invalid("Bad configuration option: x"))
        await cache.load("a", using: builder)
        #expect(cache.options(for: "a") == nil)
        #expect(cache.failure(for: "a") == "Bad configuration option: x")
    }

    @Test func appModelClearsItWhenTheSavedFileChanges() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n",
                                  runner: FixedRunner(result: ProcessResult(exitCode: 0, stdout: "hostname h\n", stderr: "", timedOut: false)))
        await model.effectiveConfig.load("web", using: model.commandBuilder)
        #expect(model.effectiveConfig.options(for: "web") != nil)
        try tmp.file(".ssh/config", "Host web\n  Port 2\n")
        model.store.load()
        #expect(model.effectiveConfig.options(for: "web") == nil)
    }
}
