import Foundation

public enum SSHKeyType: String, CaseIterable, Sendable {
    case ed25519
    case rsa   // always 4096 bits

    var arguments: [String] {
        switch self {
        case .ed25519: ["-t", "ed25519"]
        case .rsa: ["-t", "rsa", "-b", "4096"]
        }
    }

    public var defaultFileName: String {
        switch self {
        case .ed25519: "id_ed25519"
        case .rsa: "id_rsa"
        }
    }
}

public enum KeyManagerError: Error, Equatable, Sendable {
    case fileExists(String)
    /// ssh-keygen refuses passphrases shorter than five bytes.
    case passphraseTooShort
    /// askpass hands the passphrase over as one line, so it is cut at the first line break.
    case invalidPassphrase
    case wrongPassphrase
    case noAgent
    case timedOut
    /// ssh's first stderr line (English, untranslated by design).
    case failed(String)
}

/// ssh-keygen / ssh-add operations (spec §8.3). Passphrases appear only in ssh-keygen's `-N`/`-P`
/// arguments and the askpass child's environment (accepted trade-off, spec §8.4); never logged or stored.
public struct KeyManager: Sendable {
    public static let minimumPassphraseLength = 5

    private let runner: any ProcessRunning
    private let toolsDirectory: URL
    private let agentSocket: String?
    private let askPassDirectory: URL

    /// `agentSocket` nil means the user's agent (inherited `SSH_AUTH_SOCK`); tests pass their own.
    public init(runner: any ProcessRunning = ProcessRunner(),
                toolsDirectory: URL = URL(filePath: "/usr/bin"),
                agentSocket: String? = nil,
                askPassDirectory: URL = FileManager.default.temporaryDirectory) {
        self.runner = runner
        self.toolsDirectory = toolsDirectory
        self.agentSocket = agentSocket
        self.askPassDirectory = askPassDirectory
    }

    public static func isValidPassphrase(_ passphrase: String) -> Bool {
        passphrase.isEmpty || (passphrase.utf8.count >= minimumPassphraseLength && !Self.hasLineBreak(passphrase))
    }

    private static func hasLineBreak(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
    }

    public static func passphraseError(_ passphrase: String) -> KeyManagerError {
        hasLineBreak(passphrase) ? .invalidPassphrase : .passphraseTooShort
    }

    /// Never overwrites: fails if the key or its `.pub` exists. Creates the directory (0700) if needed.
    public func generate(type: SSHKeyType, at url: URL, comment: String, passphrase: String) async throws {
        let fm = FileManager.default
        for path in [url.path, url.path + ".pub"] where fm.fileExists(atPath: path) {
            throw KeyManagerError.fileExists(path)
        }
        guard Self.isValidPassphrase(passphrase) else { throw Self.passphraseError(passphrase) }
        let directory = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let result = try await run("ssh-keygen", ["-q"] + type.arguments + ["-C", comment, "-f", url.path, "-N", passphrase])
        try check(result)
    }

    public func changePassphrase(at url: URL, old: String, new: String) async throws {
        guard Self.isValidPassphrase(new) else { throw Self.passphraseError(new) }
        let result = try await run("ssh-keygen", ["-p", "-f", url.path, "-P", old, "-N", new])
        if result.exitCode != 0 && result.stderr.contains("incorrect passphrase") { throw KeyManagerError.wrongPassphrase }
        try check(result)
    }

    public func addToAgent(_ url: URL, passphrase: String?, useKeychain: Bool) async throws {
        let askPass = try AskPass.make(in: askPassDirectory)
        defer { askPass.remove() }
        let arguments = (useKeychain ? ["--apple-use-keychain"] : []) + [url.path]
        let environment = agentEnvironment.merging(askPass.environment(secret: passphrase ?? "")) { _, new in new }
        let result = try await run("ssh-add", arguments, environment: environment)
        guard result.exitCode != 0 else { return }
        if result.exitCode == 2 || result.stderr.contains("Error connecting to agent")
            || result.stderr.contains("Could not open a connection") {
            throw KeyManagerError.noAgent
        }
        if askPass.wasAsked { throw KeyManagerError.wrongPassphrase }
        throw KeyManagerError.failed(ConnectionClassifier.firstLine(result.stderr))
    }

    /// Fingerprints loaded in the agent; empty if it has none; nil if no agent is reachable.
    public func agentFingerprints() async -> Set<String>? {
        guard let result = try? await run("ssh-add", ["-l"], environment: agentEnvironment) else { return nil }
        switch result.exitCode {
        case 0: return Self.parseAgentList(result.stdout)
        case 1: return []
        default: return nil
        }
    }

    public static func parseAgentList(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(separator: " ").first { $0.hasPrefix("SHA256:") }.map(String.init)
        })
    }

    /// `fileName`, else `fileName_2`, `_3` … — a name for which neither the key nor its `.pub` exists.
    public static func nextAvailableURL(fileName: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appending(path: fileName)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) || fm.fileExists(atPath: candidate.path + ".pub") {
            candidate = directory.appending(path: "\(fileName)_\(counter)")
            counter += 1
        }
        return candidate
    }

    private var agentEnvironment: [String: String] {
        agentSocket.map { ["SSH_AUTH_SOCK": $0] } ?? [:]
    }

    private func run(_ tool: String, _ arguments: [String], environment: [String: String] = [:]) async throws -> ProcessResult {
        let result = try await runner.run(toolsDirectory.appending(path: tool), arguments: arguments,
                                          environment: environment, timeout: .seconds(30))
        if result.timedOut { throw KeyManagerError.timedOut }
        return result
    }

    private func check(_ result: ProcessResult) throws {
        guard result.exitCode == 0 else { throw KeyManagerError.failed(ConnectionClassifier.firstLine(result.stderr)) }
    }
}
