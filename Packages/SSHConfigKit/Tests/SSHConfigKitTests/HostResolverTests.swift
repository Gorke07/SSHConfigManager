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
        #expect(host == ResolvedHost(hostname: "example.com", port: 2222, hostKeyAlias: "myalias"))
        #expect(host?.lookupNames == ["myalias", "[example.com]:2222"])
    }

    @Test func withoutAliasOnlyTheHostName() {
        let host = HostResolver.parse("hostname 10.0.0.1\nport 22\n")
        #expect(host?.lookupNames == ["10.0.0.1"])
    }

    @Test func missingHostnameOrBadPortIsUnparsable() {
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
}
