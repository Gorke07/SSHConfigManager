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

/// Holds every run open until `open()`, so a test can observe how many are running at once.
final class GatedRunner: ProcessRunning, @unchecked Sendable {
    private let state = Mutex((running: 0, peak: 0, runs: 0, open: false, output: "hostname h\n"))
    var running: Int { state.withLock { $0.running } }
    var peak: Int { state.withLock { $0.peak } }
    var runs: Int { state.withLock { $0.runs } }
    func open() { state.withLock { $0.open = true } }
    func setOutput(_ text: String) { state.withLock { $0.output = text } }
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        state.withLock { $0.running += 1; $0.peak = max($0.peak, $0.running); $0.runs += 1 }
        while !state.withLock({ $0.open }) { try? await Task.sleep(for: .milliseconds(5)) }
        let output = state.withLock { $0.running -= 1; return $0.output }
        return ProcessResult(exitCode: 0, stdout: output, stderr: "", timedOut: false)
    }
}

@MainActor
struct EffectiveConfigCacheTests {
    let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))

    @Test func loadsOncePerExactAlias() async {
        let runner = PeakRunner(delay: .milliseconds(10), output: "hostname 10.0.0.1\nport 22\n")
        let cache = EffectiveConfigCache(runner: runner)
        await cache.load("web", using: builder)
        await cache.load("web", using: builder)
        #expect(runner.runs == 1)
        #expect(cache.options(for: "web")?.first("hostname") == "10.0.0.1")
        #expect(cache.options(for: "Web") == nil)
        #expect(runner.lastArguments == ["-G", "--", "web"])
    }

    @Test func differentlyCasedAliasesKeepSeparateResults() async {
        final class ByAlias: ProcessRunning, @unchecked Sendable {
            func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
                ProcessResult(exitCode: 0, stdout: "user \(arguments.last == "Web" ? "upper" : "lower")\n", stderr: "", timedOut: false)
            }
        }
        let cache = EffectiveConfigCache(runner: ByAlias())
        await cache.load("Web", using: builder)
        await cache.load("web", using: builder)
        #expect(cache.options(for: "Web")?.first("user") == "upper")
        #expect(cache.options(for: "web")?.first("user") == "lower")
        #expect(cache.options(for: "WEB") == nil)
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
        let code = "255"
        #expect(cache.failure(for: "a") == String(localized: "effective.error.exit \(code)"))
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

    @Test func threeLoadsPeakAtExactlyTwoConcurrentRuns() async {
        let runner = GatedRunner()
        let cache = EffectiveConfigCache(runner: runner)
        let tasks = ["a", "b", "c"].map { alias in Task { await cache.load(alias, using: builder) } }
        for _ in 0..<400 where runner.running < 2 { try? await Task.sleep(for: .milliseconds(5)) }
        // Give the third load every chance to (wrongly) start.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(runner.running == 2)
        #expect(runner.runs == 2)
        runner.open()
        for task in tasks { await task.value }
        #expect(runner.runs == 3)
        #expect(runner.peak == 2)
        #expect(["a", "b", "c"].allSatisfy { cache.options(for: $0) != nil })
    }

    @Test func clearThenReloadRunsSshAgainAndStoresTheNewResult() async {
        let runner = GatedRunner()
        runner.open()
        let cache = EffectiveConfigCache(runner: runner)
        await cache.load("a", using: builder)
        #expect(cache.options(for: "a")?.first("hostname") == "h")
        cache.clear()
        runner.setOutput("hostname new\n")
        await cache.load("a", using: builder)
        #expect(runner.runs == 2)
        #expect(cache.options(for: "a")?.first("hostname") == "new")
    }

    @Test func switchingTheConfigClearsTheCache() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n",
                                  runner: FixedRunner(result: ProcessResult(exitCode: 0, stdout: "hostname h\n", stderr: "", timedOut: false)))
        await model.effectiveConfig.load("web", using: model.commandBuilder)
        let before = model.effectiveConfig.generation
        let other = try tmp.file("other.conf", "Host db\n")
        #expect(model.switchConfig(to: other.path) == .switched)
        #expect(model.effectiveConfig.results.isEmpty)
        #expect(model.effectiveConfig.failures.isEmpty)
        #expect(model.effectiveConfig.generation > before)
    }

    @Test func refreshingIncludesDropsTheCacheOnlyWhenTheyChanged() async throws {
        let tmp = try TempDir()
        let extra = try tmp.file(".ssh/extra.conf", "Host inc\n  Port 1\n")
        let model = makeTestModel(tmp, config: "Include extra.conf\nHost web\n",
                                  runner: FixedRunner(result: ProcessResult(exitCode: 0, stdout: "hostname h\n", stderr: "", timedOut: false)))
        await model.effectiveConfig.load("inc", using: model.commandBuilder)
        let generation = model.effectiveConfig.generation
        model.refreshIncludes()
        #expect(model.effectiveConfig.generation == generation)
        #expect(model.effectiveConfig.options(for: "inc") != nil)
        try Data("Host inc\n  Port 2\n".utf8).write(to: extra)
        model.refreshIncludes()
        #expect(model.effectiveConfig.generation > generation)
        #expect(model.effectiveConfig.options(for: "inc") == nil)
        #expect(model.resolvedConfig(forSavedAlias: "inc")?.first("port")?.value == "2")
    }
}
