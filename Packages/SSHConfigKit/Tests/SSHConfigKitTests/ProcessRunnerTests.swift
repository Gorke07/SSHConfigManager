import Foundation
import Testing
@testable import SSHConfigKit

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
}
