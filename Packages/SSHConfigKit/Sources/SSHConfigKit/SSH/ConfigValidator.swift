import Foundation

public enum ValidationOutcome: Equatable, Sendable {
    case valid
    /// `message` is ssh's own stderr (English, untranslated by design).
    case invalid(message: String)
    case timedOut
}

/// Validates config text by writing it to a private temp file and running `ssh -G -F <file> -- <alias>`.
/// With `-F`, ssh ignores the system-wide config, so only this text is checked.
/// Relative `Include` paths still resolve against `~/.ssh`, exactly as they will at runtime.
public struct ConfigValidator: Sendable {
    private let runner: any ProcessRunning
    private let sshPath: URL

    public init(runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")) {
        self.runner = runner
        self.sshPath = sshPath
    }

    public func validate(_ text: String, probeAlias: String) async throws -> ValidationOutcome {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appending(path: "sshcm-validate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }

        let file = directory.appending(path: "config")
        guard fm.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }

        let result = try await runner.run(
            sshPath, arguments: ["-G", "-F", file.path, "--", probeAlias], environment: [:], timeout: .seconds(5))
        if result.timedOut { return .timedOut }
        if result.exitCode == 0 { return .valid }
        return .invalid(message: result.stderr
            .replacingOccurrences(of: file.path, with: "config")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
