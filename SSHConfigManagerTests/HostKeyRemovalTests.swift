import Foundation
import Synchronization
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HostKeyRemovalTests {
    static let ed = KnownHostsModelTests.ed
    static let config = "Host web\n  HostName web.example.com\n"
    static let knownHosts = """
    web.example.com ssh-ed25519 \(ed)
    |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)
    *.example.com ssh-ed25519 \(ed)
    other.example.com ssh-ed25519 \(ed)

    """

    /// `ssh -G` output for the alias (FixedRunner also answers validation; exit 0 = valid).
    func make(_ tmp: TempDir, sshG: String) -> AppModel {
        _ = try? tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = FixedRunner(result: ProcessResult(exitCode: 0, stdout: sshG, stderr: "", timedOut: false))
        return makeTestModel(tmp, config: Self.config, runner: runner)
    }

    @Test func findsPlainAndHashedEntriesButNotPatterns() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        await model.requestHostKeyRemoval(alias: "web")
        guard case .confirm(let entries) = model.hostKeyRemoval?.phase else {
            Issue.record("expected confirm, got \(String(describing: model.hostKeyRemoval))"); return
        }
        #expect(entries.map(\.lineIndex) == [0])
        // The hashed line is for "example.com", not "web.example.com"; the pattern never matches.
    }

    @Test func hostKeyAliasReplacesTheHostName() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nhostkeyalias example.com\n")
        await model.requestHostKeyRemoval(alias: "web")
        guard case .confirm(let entries) = model.hostKeyRemoval?.phase else { Issue.record("expected confirm"); return }
        // Only the alias is looked up (ssh never reads the host name's own entry then).
        #expect(entries.map(\.lineIndex) == [1])
    }

    @Test func confirmingDeletesOnlyThoseLinesAndForgetsTheTestResult() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        await model.connectionTests.test("web", using: model.commandBuilder)   // seed a result to be forgotten
        #expect(model.connectionTests.results["web"] != nil)
        await model.requestHostKeyRemoval(alias: "web")
        model.confirmHostKeyRemoval()
        #expect(model.hostKeyRemoval == nil)
        let text = try tmp.read(".ssh/known_hosts")
        #expect(!text.contains("web.example.com ssh-ed25519"))
        #expect(text.contains("*.example.com"))
        #expect(text.contains("other.example.com"))
        #expect(model.connectionTests.results["web"] == nil)
    }

    @Test func nothingFoundListsTheNamesThatWereTried() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname 10.9.9.9\nport 2200\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.phase == .nothingFound(["[10.9.9.9]:2200"]))
    }

    @Test func resolveFailureIsShown() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = FixedRunner(result: ProcessResult(exitCode: 255, stdout: "", stderr: "Bad configuration option: foo\n", timedOut: false))
        let model = makeTestModel(tmp, config: Self.config, runner: runner)
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.phase == .failed(String(localized: "hostKeyRemoval.resolveFailed \("Bad configuration option: foo")")))
    }

    @Test func aChangeOfTheFileWhileConfirmingDeletesNothing() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        await model.requestHostKeyRemoval(alias: "web")
        try tmp.file(".ssh/known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.knownHosts)
        model.knownHosts.load()
        model.confirmHostKeyRemoval()
        #expect(try tmp.read(".ssh/known_hosts").contains("web.example.com ssh-ed25519"))
        #expect(model.errorMessage == String(localized: "knownHosts.staleSelection"))
    }

    @Test func unsavedAliasesAreRefused() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname x\nport 22\n")
        await model.requestHostKeyRemoval(alias: "not-in-file")
        #expect(model.hostKeyRemoval == nil)
        #expect(model.errorMessage == String(localized: "connect.notSaved"))
    }

    @Test(.timeLimit(.minutes(1))) func cancellingWhileResolvingDropsTheLateAnswer() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = SequencedGateRunner(outputs: ["hostname web.example.com\nport 22\n"])
        let model = makeTestModel(tmp, config: Self.config, runner: runner)
        let task = Task { await model.requestHostKeyRemoval(alias: "web") }
        await runner.waitForEntry(0)
        #expect(model.hostKeyRemoval?.phase == .resolving)
        model.cancelHostKeyRemoval()
        runner.release(0)   // the late answer arrives after the cancel
        await task.value
        #expect(model.hostKeyRemoval == nil)
    }

    @Test(.timeLimit(.minutes(1))) func aSecondRequestReplacesTheFirstAndTheFirstLateAnswerIsDropped() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        // First ssh -G answers a host with no entries, the second one a host that has them.
        let runner = SequencedGateRunner(outputs: ["hostname 10.9.9.9\nport 22\n", "hostname web.example.com\nport 22\n"])
        let model = makeTestModel(tmp, config: Self.config, runner: runner)
        let first = Task { await model.requestHostKeyRemoval(alias: "web") }
        await runner.waitForEntry(0)
        let firstID = model.hostKeyRemoval?.id
        let second = Task { await model.requestHostKeyRemoval(alias: "web") }
        await runner.waitForEntry(1)
        #expect(model.hostKeyRemoval?.id != firstID)
        runner.release(0)
        await first.value   // the first answer (would be .nothingFound) arrives late and must be dropped
        #expect(model.hostKeyRemoval?.phase == .resolving)
        runner.release(1)
        await second.value
        guard case .confirm(let entries) = model.hostKeyRemoval?.phase else {
            Issue.record("expected confirm, got \(String(describing: model.hostKeyRemoval))"); return
        }
        #expect(entries.map(\.lineIndex) == [0])
    }

    @Test func switchingTheFileWhileConfirmingDeletesNothing() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        let otherURL = try tmp.file("other_known_hosts", Self.knownHosts)
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.switchKnownHosts(to: otherURL.path))
        model.confirmHostKeyRemoval()
        #expect(try tmp.read(".ssh/known_hosts") == Self.knownHosts)
        #expect(try String(contentsOf: otherURL, encoding: .utf8) == Self.knownHosts)
        #expect(model.errorMessage == String(localized: "knownHosts.staleSelection"))
    }

    @Test func anUnreadableKnownHostsFileIsAnErrorNotNothingFound() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        try Data([0xFF, 0xFE]).write(to: tmp.url.appendingPathComponent(".ssh/known_hosts"))
        model.knownHosts.load()
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.phase == .failed(String(localized: "knownHosts.notUTF8")))
    }

    @Test func checkHostIPAddsANote() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\ncheckhostip yes\nuserknownhostsfile ~/.ssh/known_hosts ~/.ssh/known_hosts2\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.checkHostIP == true)
        #expect(model.hostKeyRemoval?.notes == [String(localized: "hostKeyRemoval.checkHostIPNote")])
    }

    @Test func noNotesWhenSshReadsTheManagedFile() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\ncheckhostip no\nuserknownhostsfile ~/.ssh/known_hosts ~/.ssh/known_hosts2\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.otherKnownHostsFile == nil)
        #expect(model.hostKeyRemoval?.notes == [])
    }

    @Test func anotherUserKnownHostsFileAddsANote() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nuserknownhostsfile ~/.ssh/other_hosts /etc/ssh/extra\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.otherKnownHostsFile == "~/.ssh/other_hosts")
        let file = "~/.ssh/other_hosts"
        #expect(model.hostKeyRemoval?.notes == [String(localized: "hostKeyRemoval.otherFileNote \(file)")])
    }

    @Test func anAbsoluteUserKnownHostsFileIsComparedStandardized() async throws {
        let tmp = try TempDir()
        let path = tmp.url.path + "/.ssh/../.ssh/known_hosts"
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nuserknownhostsfile \(path)\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.otherKnownHostsFile == nil)
    }

    @Test func aQuotedUserKnownHostsFileWithSpacesIsRecognised() async throws {
        let tmp = try TempDir()
        // ssh -G prints it unquoted and expanded; the path has a space.
        _ = try tmp.file("My Hosts/known_hosts", Self.knownHosts)
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nuserknownhostsfile /x/other \(tmp.url.path)/My Hosts/known_hosts\n")
        #expect(model.switchKnownHosts(to: tmp.url.path + "/My Hosts/known_hosts"))
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.otherKnownHostsFile == nil)
    }

    @Test func percentDAndTildeExpandToTheHome() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nuserknownhostsfile %d/.ssh/known_hosts\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.otherKnownHostsFile == nil)
    }

    @Test func aSymlinkedPathIsTheSameFile() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nuserknownhostsfile \(tmp.url.path)/link/known_hosts\n")
        try FileManager.default.createSymbolicLink(at: tmp.url.appendingPathComponent("link"), withDestinationURL: tmp.url.appendingPathComponent(".ssh"))
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.otherKnownHostsFile == nil)
    }

    @Test(.timeLimit(.minutes(1))) func cancellingTheFlowCancelsTheRunningSsh() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = CancellableRunner()
        let model = makeTestModel(tmp, config: Self.config, runner: runner)
        model.startHostKeyRemoval(alias: "web")
        for await _ in runner.entries { break }   // wait until the fake ssh -G has started
        model.cancelHostKeyRemoval()
        for await _ in runner.cancellations { break }
        #expect(runner.cancelledCount == 1)
        #expect(model.hostKeyRemoval == nil)
    }

    /// The real runner does not throw when it kills ssh: it returns the signal number as exit code.
    @Test(.timeLimit(.minutes(1))) func aKilledSshEndsTheFlowWithoutAStaleResult() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = CancellableRunner(killedBySignal: true)
        let model = makeTestModel(tmp, config: Self.config, runner: runner)
        model.startHostKeyRemoval(alias: "web")
        for await _ in runner.entries { break }
        let task = model.hostKeyRemovalTask
        model.cancelHostKeyRemoval()
        await task?.value   // the flow has fully ended: a late failed/answer would show up now
        for await _ in runner.cancellations { break }
        #expect(model.hostKeyRemoval == nil)
        #expect(model.errorMessage == nil)
    }
}

/// Suspends until its task is cancelled, then reports it and throws like ProcessRunner does.
final class CancellableRunner: ProcessRunning, @unchecked Sendable {
    let entries: AsyncStream<Void>
    private let entered: AsyncStream<Void>.Continuation
    let cancellations: AsyncStream<Void>
    private let cancelled: AsyncStream<Void>.Continuation
    private let count = Mutex(0)
    /// Return a SIGTERM-killed result (exit code 15, no output) instead of throwing, like ProcessRunner.
    private let killedBySignal: Bool
    var cancelledCount: Int { count.withLock { $0 } }
    init(killedBySignal: Bool = false) {
        self.killedBySignal = killedBySignal
        (entries, entered) = AsyncStream.makeStream()
        (cancellations, cancelled) = AsyncStream.makeStream()
    }
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        entered.yield()
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            count.withLock { $0 += 1 }
            cancelled.yield()
            if killedBySignal { return ProcessResult(exitCode: 15, stdout: "", stderr: "", timedOut: false) }
            throw CancellationError()
        }
        return ProcessResult(exitCode: 0, stdout: "hostname web.example.com\nport 22\n", stderr: "", timedOut: false)
    }
}

/// Run n suspends until `release(n)` and then answers `outputs[n]`; `waitForEntry(n)` returns once run n has started.
final class SequencedGateRunner: ProcessRunning, @unchecked Sendable {
    private struct State {
        var started = 0
        var entered = Set<Int>()
        var gates: [Int: CheckedContinuation<Void, Never>] = [:]
        var released = Set<Int>()
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    }
    private let state = Mutex(State())
    private let outputs: [String]
    init(outputs: [String]) { self.outputs = outputs }

    func waitForEntry(_ index: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { state -> Bool in
                if state.entered.contains(index) { return true }
                state.waiters[index] = continuation
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func release(_ index: Int) {
        let gate = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released.insert(index)
            return state.gates.removeValue(forKey: index)
        }
        gate?.resume()
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        let index = state.withLock { state -> Int in defer { state.started += 1 }; return state.started }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let (pass, waiter) = state.withLock { state -> (Bool, CheckedContinuation<Void, Never>?) in
                state.entered.insert(index)
                let waiter = state.waiters.removeValue(forKey: index)
                if state.released.contains(index) { return (true, waiter) }
                state.gates[index] = continuation   // registered before the waiter is told
                return (false, waiter)
            }
            waiter?.resume()
            if pass { continuation.resume() }
        }
        return ProcessResult(exitCode: 0, stdout: outputs[min(index, outputs.count - 1)], stderr: "", timedOut: false)
    }
}
