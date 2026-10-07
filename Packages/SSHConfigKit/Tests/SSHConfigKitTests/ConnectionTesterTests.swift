import Foundation
import Synchronization
import Testing
@testable import SSHConfigKit

struct ConnectionTesterTests {
    static let changedKey = """
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    Host key verification failed.
    """

    @Test(arguments: [
        (Int32(0), "", false, ConnectionStatus.reachable),
        (255, changedKey, false, .hostKeyChanged),
        (255, "No ED25519 host key is known for x and you have requested strict checking.\r\nHost key verification failed.\r\n", false, .unknownHostKey),
        (255, "ssh: Could not resolve hostname nope.invalid: nodename nor servname provided, or not known\r\n", false, .dnsFailure),
        (255, "ssh: connect to host 127.0.0.1 port 1: Connection refused\r\n", false, .connectionRefused),
        (255, "ssh: connect to host 10.255.255.1 port 22: Operation timed out\r\n", false, .timeout),
        (255, "deploy@10.0.0.1: Permission denied (publickey,password).\r\n", false, .authenticationRequired),
        (255, "Received disconnect from 1.2.3.4 port 22:2: Too many authentication failures\r\n", false, .authenticationRequired),
        (255, "", true, .timeout),
        (255, "kex_exchange_identification: read: Connection reset by peer\r\n", false, .other),
        (1, "PTY allocation request failed\r\nHi user! You've successfully authenticated, but GitHub does not provide shell access.\r\n", false, .reachable),
    ])
    func classification(exitCode: Int32, stderr: String, timedOut: Bool, expected: ConnectionStatus) {
        #expect(ConnectionClassifier.classify(exitCode: exitCode, stderr: stderr, timedOut: timedOut) == expected)
    }

    @Test func firstLineSkipsBannersAndBlankLines() {
        #expect(ConnectionClassifier.firstLine("\r\n  \nssh: boom\r\nnext") == "ssh: boom")
        #expect(ConnectionClassifier.firstLine(Self.changedKey) == "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @")
    }

    @Test func testBuildsSafeArguments() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/x/custom"), homeDirectory: URL(filePath: "/h"))
        let result = await ConnectionTester(commandBuilder: builder, runner: fake).test(alias: "web")
        #expect(result == ConnectionTestResult(status: .reachable, detail: ""))
        #expect(try #require(fake.calls.first) == ["-F", "/x/custom", "-T",
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=yes",
            "-o", "ControlPath=none", "--", "web", "exit"])
    }

    @Test func runnerErrorBecomesOther() async {
        let failing = FailingRunner()
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let result = await ConnectionTester(commandBuilder: builder, runner: failing).test(alias: "a")
        #expect(result.status == .other)
    }

    @Test func testAllLimitsConcurrencyAndReportsEveryAlias() async {
        let fake = FakeRunner(delay: .milliseconds(50)) { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let collected = Collected()
        let aliases = (1...10).map { "h\($0)" }
        await ConnectionTester(commandBuilder: builder, runner: fake).testAll(aliases, maxConcurrent: 4) { alias, _ in
            collected.add(alias)
        }
        #expect(fake.maxConcurrent <= 4)
        #expect(fake.maxConcurrent >= 2)
        #expect(collected.values.sorted() == aliases.sorted())
    }

    @Test func cancelledTestAllReportsNothingAndStopsQueueing() async {
        let fake = FakeRunner(delay: .milliseconds(300)) { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let collected = Collected()
        let task = Task {
            await ConnectionTester(commandBuilder: builder, runner: fake).testAll((1...10).map { "h\($0)" }, maxConcurrent: 4) { alias, _ in
                collected.add(alias)
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        #expect(collected.values.isEmpty)
        #expect(fake.calls.count <= 4)
    }
}

private struct FailingRunner: ProcessRunning {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        throw CocoaError(.fileNoSuchFile)
    }
}

private final class Collected: Sendable {
    private let storage = Mutex<[String]>([])
    func add(_ value: String) { storage.withLock { $0.append(value) } }
    var values: [String] { storage.withLock { $0 } }
}
