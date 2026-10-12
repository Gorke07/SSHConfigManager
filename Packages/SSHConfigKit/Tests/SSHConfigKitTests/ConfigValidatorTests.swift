import Foundation
import Testing
@testable import SSHConfigKit

struct ConfigValidatorTests {
    let validator = ConfigValidator()

    @Test func validConfigPasses() async throws {
        let outcome = try await validator.validate("Host a\n  HostName 10.0.0.1\n  Port 2222\n", probeAlias: "a")
        #expect(outcome == .valid)
    }

    @Test func emptyConfigPasses() async throws {
        #expect(try await validator.validate("", probeAlias: "localhost") == .valid)
    }

    @Test func unknownOptionFailsWithSshMessage() async throws {
        let outcome = try await validator.validate("Host a\n  Bogus yes\n", probeAlias: "a")
        guard case .invalid(let message) = outcome else {
            Issue.record("invalid bekleniyordu: \(outcome)")
            return
        }
        #expect(message.contains("Bad configuration option: bogus"))
    }

    @Test func badPortFails() async throws {
        let outcome = try await validator.validate("Host a\n  Port abc\n", probeAlias: "a")
        guard case .invalid(let message) = outcome else {
            Issue.record("invalid bekleniyordu: \(outcome)")
            return
        }
        #expect(message.contains("Bad port"))
    }

    @Test func passesConfigFileAndAliasAfterDoubleDash() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        _ = try await ConfigValidator(runner: fake).validate("", probeAlias: "-oProxyCommand=x")
        let args = try #require(fake.calls.first)
        #expect(args.first == "-G")
        #expect(args[1] == "-F")
        #expect(Array(args.suffix(2)) == ["--", "-oProxyCommand=x"])
    }

    @Test func timeoutIsReported() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 15, stdout: "", stderr: "", timedOut: true) }
        #expect(try await ConfigValidator(runner: fake).validate("", probeAlias: "a") == .timedOut)
    }

    @Test(arguments: ["a,b", "-jump", "web$1"])
    func probeThatIsNoValidDestinationFallsBackToLocalhost(alias: String) async throws {
        let fake = FakeRunner { args in
            args.last == "localhost"
                ? ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
                : ProcessResult(exitCode: 255, stdout: "", stderr: "hostname contains invalid characters\n", timedOut: false)
        }
        #expect(try await ConfigValidator(runner: fake).validate("Host \(alias)\n", probeAlias: alias) == .valid)
        #expect(fake.calls.map(\.last) == [alias, "localhost"])
    }

    @Test func fallbackProbeStillReportsFileErrors() async throws {
        let fake = FakeRunner { _ in
            ProcessResult(exitCode: 255, stdout: "", stderr: "hostname contains invalid characters\n", timedOut: false)
        }
        let outcome = try await ConfigValidator(runner: fake).validate("Host a,b\n", probeAlias: "a,b")
        #expect(outcome == .invalid(message: "hostname contains invalid characters"))
        #expect(fake.calls.count == 2)
    }

    @Test func realSshAcceptsAFileWhoseFirstAliasIsNoDestination() async throws {
        #expect(try await validator.validate("Host a,b\n  User u\n", probeAlias: "a,b") == .valid)
        #expect(try await validator.validate("Host -jump\n  Bogus x\n", probeAlias: "-jump") != .valid)
    }

    @Test func otherFailuresDoNotRetry() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 255, stdout: "", stderr: "Bad port\n", timedOut: false) }
        _ = try await ConfigValidator(runner: fake).validate("", probeAlias: "a")
        #expect(fake.calls.count == 1)
    }
}
