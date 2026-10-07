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
}
