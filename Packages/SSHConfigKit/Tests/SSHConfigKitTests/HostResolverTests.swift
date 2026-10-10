import Foundation
import Synchronization
import Testing
@testable import SSHConfigKit

/// Records the last arguments and returns a fixed result.
final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    let result: ProcessResult
    private let lock = Mutex<[String]>([])
    var lastArguments: [String] { lock.withLock { $0 } }
    init(_ result: ProcessResult) { self.result = result }
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        lock.withLock { $0 = arguments }
        return result
    }
}

struct HostResolverTests {
    static let output = """
    user me
    hostname example.com
    port 2222
    hostkeyalias myalias
    userknownhostsfile /h/.ssh/known_hosts /h/.ssh/known_hosts2

    """

    @Test func parsesHostnamePortAndAlias() {
        let host = HostResolver.parse(Self.output)
        #expect(host == ResolvedHost(hostname: "example.com", port: 2222, hostKeyAlias: "myalias",
                                     userKnownHostsFiles: ["/h/.ssh/known_hosts", "/h/.ssh/known_hosts2"]))
        #expect(host?.lookupNames == ["myalias", "[example.com]:2222"])
    }

    @Test func withoutAliasOnlyTheHostName() {
        let host = HostResolver.parse("hostname 10.0.0.1\nport 22\n")
        #expect(host?.lookupNames == ["10.0.0.1"])
    }

    @Test func checkHostIPIsReadFromTheYesValue() {
        #expect(HostResolver.parse("hostname a\nport 22\ncheckhostip yes\n")?.checkHostIP == true)
        #expect(HostResolver.parse("hostname a\nport 22\ncheckhostip no\n")?.checkHostIP == false)
        #expect(HostResolver.parse("hostname a\nport 22\n")?.checkHostIP == false)
    }

    @Test func userKnownHostsFilesAreSplitOnSpaces() {
        let host = HostResolver.parse("hostname a\nport 22\nuserknownhostsfile ~/.ssh/known_hosts ~/.ssh/known_hosts2\n")
        #expect(host?.userKnownHostsFiles == ["~/.ssh/known_hosts", "~/.ssh/known_hosts2"])
        #expect(HostResolver.parse("hostname a\nport 22\n")?.userKnownHostsFiles == [])
    }

    @Test func parseReturnsNilWithoutHostnameOrWithBadPort() {
        #expect(HostResolver.parse("port 22\n") == nil)
        #expect(HostResolver.parse("hostname a\nport x\n") == nil)
    }

    @Test func runsSshGWithTheConfigAndTheAliasAfterDoubleDash() async throws {
        let runner = RecordingRunner(ProcessResult(exitCode: 0, stdout: Self.output, stderr: "", timedOut: false))
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/tmp/other/config"), homeDirectory: URL(filePath: "/h"))
        let host = try await HostResolver(commandBuilder: builder, runner: runner).resolve(alias: "-oProxyCommand=x")
        #expect(host.hostname == "example.com")
        #expect(runner.lastArguments == ["-F", "/tmp/other/config", "-G", "--", "-oProxyCommand=x"])
    }

    @Test func failureAndTimeoutAreReported() async {
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let failing = RecordingRunner(ProcessResult(exitCode: 255, stdout: "", stderr: "Bad configuration option\n", timedOut: false))
        await #expect(throws: HostResolverError.failed("Bad configuration option")) {
            try await HostResolver(commandBuilder: builder, runner: failing).resolve(alias: "a")
        }
        let slow = RecordingRunner(ProcessResult(exitCode: 15, stdout: "", stderr: "", timedOut: true))
        await #expect(throws: HostResolverError.timedOut) {
            try await HostResolver(commandBuilder: builder, runner: slow).resolve(alias: "a")
        }
    }

    @Test func firstValueWins() {
        let host = HostResolver.parse("hostname first\nhostname second\nport 22\nport 99\n")
        #expect(host == ResolvedHost(hostname: "first", port: 22, hostKeyAlias: nil))
    }

    @Test func parsesCRLFOutput() {
        #expect(HostResolver.parse("hostname a\r\nport 2222\r\n") == ResolvedHost(hostname: "a", port: 2222, hostKeyAlias: nil))
    }

    @Test func aliasNoneIsNil() {
        #expect(HostResolver.parse("hostname a\nport 22\nhostkeyalias none\n")?.hostKeyAlias == nil)
    }

    @Test func missingPortDefaultsTo22() {
        #expect(HostResolver.parse("hostname a\n")?.port == 22)
    }

    @Test func outOfRangePortsAreRejected() {
        #expect(HostResolver.parse("hostname a\nport 0\n") == nil)
        #expect(HostResolver.parse("hostname a\nport 70000\n") == nil)
    }

    @Test func valuesWithSpacesDoNotBreakParsing() {
        let host = HostResolver.parse("userknownhostsfile /a b/known_hosts /c/known_hosts2\nhostname a\nport 22\n")
        #expect(host?.hostname == "a")
    }

    // `ssh -G` (checked with -F <temp>) prints `UserKnownHostsFile "/tmp/a b/kh" ~/.ssh/kh2 %d/foo` as
    // `userknownhostsfile /tmp/a b/kh /Users/x/.ssh/kh2 /Users/x/foo`: unquoted, expanded, space-joined.
    @Test func aPathWithSpacesIsOneOfTheCandidates() {
        let host = HostResolver.parse("hostname a\nport 22\nuserknownhostsfile /tmp/a b/kh /Users/x/.ssh/kh2\n")
        #expect(host?.userKnownHostsFileCandidates.contains("/tmp/a b/kh") == true)
        #expect(host?.userKnownHostsFileCandidates.contains("/Users/x/.ssh/kh2") == true)
    }

    @Test func quotedPathsAreUnquoted() {
        let host = HostResolver.parse("hostname a\nport 22\nuserknownhostsfile \"/tmp/a b/kh\" /x/kh2\n")
        #expect(host?.userKnownHostsFiles == ["/tmp/a b/kh", "/x/kh2"])
    }

    @Test func valueIsTrimmed() {
        #expect(HostResolver.parse("hostname   a  \nport 22\n")?.hostname == "a")
    }

    @Test func uppercaseHostnameIsLowercasedInLookupNames() {
        #expect(HostResolver.parse("hostname Example.COM\nport 22\n")?.lookupNames == ["example.com"])
    }

    @Test func throwingRunnerMapsToFailed() async {
        struct Boom: Error {}
        struct Throwing: ProcessRunning {
            func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult { throw Boom() }
        }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        await #expect {
            try await HostResolver(commandBuilder: builder, runner: Throwing()).resolve(alias: "a")
        } throws: { error in
            if case .failed = error as? HostResolverError { return true } else { return false }
        }
    }

    @Test func cancellationIsRethrown() async {
        struct Cancelling: ProcessRunning {
            func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult { throw CancellationError() }
        }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        await #expect(throws: CancellationError.self) {
            try await HostResolver(commandBuilder: builder, runner: Cancelling()).resolve(alias: "a")
        }
    }

    @Test func successWithUnparsableOutputThrowsUnparsable() async {
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let runner = RecordingRunner(ProcessResult(exitCode: 0, stdout: "garbage\n", stderr: "", timedOut: false))
        await #expect(throws: HostResolverError.unparsable) {
            try await HostResolver(commandBuilder: builder, runner: runner).resolve(alias: "a")
        }
    }
}
