import Foundation
import Testing
@testable import SSHConfigKit

@Suite(.timeLimit(.minutes(1)))
struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test func capturesStdoutAndExitCode() async throws {
        let result = try await runner.run(URL(filePath: "/bin/echo"), arguments: ["hi"], environment: [:], timeout: .seconds(5))
        #expect(result == ProcessResult(exitCode: 0, stdout: "hi\n", stderr: "", timedOut: false))
    }

    @Test func capturesStderrAndNonZeroExit() async throws {
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo err >&2; exit 3"], environment: [:], timeout: .seconds(5))
        #expect(result.exitCode == 3)
        #expect(result.stderr == "err\n")
    }

    @Test func timeoutTerminatesTheProcess() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await runner.run(URL(filePath: "/bin/sleep"), arguments: ["10"], environment: [:], timeout: .milliseconds(200))
        #expect(result.timedOut)
        #expect(clock.now - started < .seconds(3))
    }

    @Test func forcesCLocaleAndMergesEnvironment() async throws {
        let result = try await runner.run(URL(filePath: "/usr/bin/env"), arguments: [], environment: ["SSHCM_TEST": "1", "LC_ALL": "tr_TR.UTF-8"], timeout: .seconds(5))
        #expect(result.stdout.contains("LC_ALL=C\n"))
        #expect(result.stdout.contains("SSHCM_TEST=1\n"))
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' a"], environment: [:], timeout: .seconds(10))
        #expect(result.stdout.utf8.count == 300_000)
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await runner.run(URL(filePath: "/nonexistent/tool"), arguments: [], environment: [:], timeout: .seconds(1))
        }
    }

    @Test func stdinIsEmpty() async throws {
        let result = try await runner.run(URL(filePath: "/bin/cat"), arguments: [], environment: [:], timeout: .seconds(5))
        #expect(result.stdout.isEmpty)
        #expect(!result.timedOut)
    }

    @Test func grandchildHoldingPipeDoesNotHang() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "(sleep 5 &); echo hi"], environment: [:], timeout: .seconds(10))
        #expect(clock.now - started < .seconds(3))
        #expect(result.stdout == "hi\n")
        #expect(result.exitCode == 0)
        #expect(!result.timedOut)
    }

    @Test func sigkillEscalation() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "trap '' TERM; sleep 10"], environment: [:], timeout: .milliseconds(200))
        #expect(clock.now - started < .seconds(4))
        #expect(result.timedOut)
    }

    @Test func cancellationTerminatesChild() async throws {
        let runner = self.runner
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await runner.run(URL(filePath: "/bin/sleep"), arguments: ["10"], environment: [:], timeout: .seconds(30))
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        _ = try await task.value
        #expect(clock.now - started < .seconds(3))
    }

    /// Starts `sh` which backgrounds `sleep 30` (a grandchild), records its pid, then sleeps itself.
    /// Returns the grandchild pid once the script has written it.
    private func startTreeAndReadGrandchild(pidFile: URL) async throws -> pid_t {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8),
               text.hasSuffix("\n"), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    private func isGone(_ pid: pid_t) async -> Bool {
        for _ in 0..<60 {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test func cancelKillsGrandchildren() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sshcm-pg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pidFile = dir.appending(path: "pid")
        let script = "sleep 30 & echo $! > '\(pidFile.path)'; sleep 30"
        let runner = self.runner
        let task = Task {
            try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: [:], timeout: .seconds(60))
        }
        let grandchild = try await startTreeAndReadGrandchild(pidFile: pidFile)
        #expect(kill(grandchild, 0) == 0)
        task.cancel()
        _ = try await task.value
        let gone = await isGone(grandchild)
        if !gone { kill(grandchild, SIGKILL) }   // our own test child only
        #expect(gone)
    }

    @Test func cancelAfterLeaderExitStillKillsGroupMembers() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sshcm-pg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pidFile = dir.appending(path: "pid")
        // The leader exits at once; the grandchild keeps stdout open.
        let script = "sleep 30 & echo $! > '\(pidFile.path)'"
        let runner = self.runner
        let task = Task {
            try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: [:], timeout: .seconds(60))
        }
        let grandchild = try await startTreeAndReadGrandchild(pidFile: pidFile)
        task.cancel()
        _ = try await task.value
        let gone = await isGone(grandchild)
        if !gone { kill(grandchild, SIGKILL) }   // our own test child only
        #expect(gone)
    }

    @Test func timeoutKillsGrandchildrenIncludingTermIgnoring() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sshcm-pg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pidFile = dir.appending(path: "pid")
        let script = "trap '' TERM; (trap '' TERM; exec sleep 30) & echo $! > '\(pidFile.path)'; sleep 30"
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: [:], timeout: .milliseconds(800))
        #expect(result.timedOut)
        let grandchild = try await startTreeAndReadGrandchild(pidFile: pidFile)
        let gone = await isGone(grandchild)
        if !gone { kill(grandchild, SIGKILL) }
        #expect(gone)
    }

    @Test func cancelEscalatesToSigkill() async throws {
        let runner = self.runner
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "trap '' TERM; sleep 10"], environment: [:], timeout: .seconds(30))
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        _ = try await task.value
        #expect(clock.now - started < .seconds(4))
    }

    @Test func childIsItsOwnProcessGroupLeader() async throws {
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "ps -o pid=,pgid= -p $$"], environment: [:], timeout: .seconds(5))
        let parts = result.stdout.split(separator: " ").compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(parts.count == 2)
        #expect(parts.first == parts.last)
        #expect(parts.first != getpgrp())
    }
}
