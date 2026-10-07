import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
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

    @Test func hostKeyAliasIsAlsoLookedUp() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nhostkeyalias example.com\n")
        await model.requestHostKeyRemoval(alias: "web")
        guard case .confirm(let entries) = model.hostKeyRemoval?.phase else { Issue.record("expected confirm"); return }
        #expect(entries.map(\.lineIndex) == [0, 1])
    }

    @Test func confirmingDeletesOnlyThoseLinesAndForgetsTheTestResult() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
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

    @Test func cancellingWhileResolvingDropsTheLateAnswer() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let model = makeTestModel(tmp, config: Self.config, runner: DelayedRunner(
            delay: .milliseconds(300),
            result: ProcessResult(exitCode: 0, stdout: "hostname web.example.com\nport 22\n", stderr: "", timedOut: false)))
        let task = Task { await model.requestHostKeyRemoval(alias: "web") }
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hostKeyRemoval?.phase == .resolving)
        model.cancelHostKeyRemoval()
        await task.value
        #expect(model.hostKeyRemoval == nil)
    }
}
