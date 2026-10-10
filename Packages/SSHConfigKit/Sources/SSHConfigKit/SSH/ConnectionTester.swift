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
        // Match only lines in ssh's own message forms, never a substring anywhere: a server
        // banner (also on stderr) may say "Permission denied" or "Connection refused" in prose.
        let lines = lines(of: stderr)
        let rules: [((String) -> Bool, ConnectionStatus)] = [
            ({ $0.hasPrefix("@") && $0.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") }, .hostKeyChanged),
            ({ $0.hasPrefix("Host key verification failed") }, .unknownHostKey),
            ({ $0.hasPrefix("ssh: Could not resolve hostname") }, .dnsFailure),
            ({ $0.hasPrefix("ssh: connect to host") && $0.contains("Connection refused") }, .connectionRefused),
            ({ ($0.hasPrefix("ssh: connect to host") && ($0.contains("Operation timed out") || $0.contains("Connection timed out")))
                || $0.hasPrefix("Connection timed out during") }, .timeout),
            (isPermissionDenied, .authenticationRequired),
            ({ $0.hasPrefix("Received disconnect from") && $0.contains("Too many authentication failures") }, .authenticationRequired),
            ({ $0.hasPrefix("ssh:") && $0.contains("keyboard-interactive") }, .authenticationRequired),
        ]
        return rules.first { rule in lines.contains(where: rule.0) }?.1 ?? .other
    }

    /// OpenSSH's "[user@host: ]Permission denied (publickey,password)." or
    /// "Permission denied, please try again.". The method list has no spaces, so prose does not match.
    private static func isPermissionDenied(_ line: String) -> Bool {
        var rest = Substring(line)
        if let colon = rest.range(of: ": "), rest[..<colon.lowerBound].contains("@"), !rest[..<colon.lowerBound].contains(" ") {
            rest = rest[colon.upperBound...]
        }
        if rest.hasPrefix("Permission denied, please try again") { return true }
        guard rest.hasPrefix("Permission denied (") else { return false }
        let methods = rest.dropFirst("Permission denied (".count).prefix { $0 != ")" }
        return rest.contains(")") && !methods.isEmpty
            && methods.allSatisfy { $0.isLetter || $0.isNumber || $0 == "," || $0 == "-" }
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// First non-blank line that is not a row of "@" banner characters or a "Warning:" notice
    /// (e.g. "Warning: Permanently added ... to the list of known hosts.").
    public static func firstLine(_ text: String) -> String {
        lines(of: text).first { !$0.allSatisfy { $0 == "@" } && !$0.hasPrefix("Warning:") } ?? ""
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
