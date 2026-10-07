import Foundation

public enum ConnectionStatus: Equatable, Sendable {
    case reachable
    case authenticationRequired
    case hostKeyChanged
    case unknownHostKey
    case timeout
    case dnsFailure
    case connectionRefused
    /// See `ConnectionTestResult.detail` for ssh's message.
    case other
}

public struct ConnectionTestResult: Equatable, Sendable {
    public let status: ConnectionStatus
    /// First meaningful stderr line from ssh (untranslated).
    public let detail: String

    public init(status: ConnectionStatus, detail: String) {
        self.status = status
        self.detail = detail
    }
}

/// Classifies ssh output. Relies on OpenSSH's English messages; the runner forces `LC_ALL=C`.
public enum ConnectionClassifier {
    public static func classify(exitCode: Int32, stderr: String, timedOut: Bool) -> ConnectionStatus {
        if timedOut { return .timeout }
        // ssh's own failures exit 255; any other code is the remote command's
        // (GitHub/GitLab exit 1 after successful authentication).
        if exitCode != 255 { return .reachable }
        let rules: [(String, ConnectionStatus)] = [
            ("REMOTE HOST IDENTIFICATION HAS CHANGED", .hostKeyChanged),
            ("Host key verification failed", .unknownHostKey),
            ("Could not resolve hostname", .dnsFailure),
            ("Connection refused", .connectionRefused),
            ("Operation timed out", .timeout),
            ("Connection timed out", .timeout),
            ("Permission denied", .authenticationRequired),
            ("Too many authentication failures", .authenticationRequired),
            ("keyboard-interactive", .authenticationRequired),
        ]
        return rules.first { stderr.contains($0.0) }?.1 ?? .other
    }

    /// First non-blank line that is not a row of "@" banner characters.
    public static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.allSatisfy { $0 == "@" } } ?? ""
    }
}

public struct ConnectionTester: Sendable {
    /// `-T` suppresses "Pseudo-terminal will not be allocated"; `ControlPath=none`
    /// keeps an existing multiplexed connection from masking the result.
    public static let options = [
        "-T",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ControlPath=none",
    ]

    private let commandBuilder: SSHCommandBuilder
    private let runner: any ProcessRunning
    private let sshPath: URL

    public init(commandBuilder: SSHCommandBuilder, runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")) {
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.sshPath = sshPath
    }

    public func test(alias: String) async -> ConnectionTestResult {
        let arguments = commandBuilder.sshArguments(options: Self.options, alias: alias) + ["exit"]
        do {
            let result = try await runner.run(sshPath, arguments: arguments, environment: [:], timeout: .seconds(10))
            return ConnectionTestResult(
                status: ConnectionClassifier.classify(exitCode: result.exitCode, stderr: result.stderr, timedOut: result.timedOut),
                detail: ConnectionClassifier.firstLine(result.stderr))
        } catch {
            return ConnectionTestResult(status: .other, detail: error.localizedDescription)
        }
    }

    public func testAll(
        _ aliases: [String],
        maxConcurrent: Int = 4,
        onResult: @escaping @Sendable (String, ConnectionTestResult) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var pending = aliases.makeIterator()
            func startNext() {
                guard !Task.isCancelled, let alias = pending.next() else { return }
                group.addTask {
                    let result = await self.test(alias: alias)
                    // A cancelled run must not report fake failures for hosts it never really tested.
                    if !Task.isCancelled { await onResult(alias, result) }
                }
            }
            for _ in 0..<max(maxConcurrent, 1) { startNext() }
            while await group.next() != nil { startNext() }
        }
    }
}
