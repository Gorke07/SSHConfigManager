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
    /// The key is encrypted and no passphrase was given.
    case passphraseRequired
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
    /// The hard-link step; tests replace it to force the no-hard-link fallback.
    var linker: @Sendable (String, String) -> Int32 = { link($0, $1) }

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
        // ssh-keygen only asks before replacing the private key, so it never writes the final paths: it
        // generates into a private temp directory beside them, and the files are then link(2)ed into place,
        // which fails if either already exists (nothing is ever overwritten).
        Self.removeStaleTempDirectories(in: directory, olderThan: .seconds(300))
        let temp = directory.appending(path: ".sshcm-keygen-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        let tempKey = temp.appending(path: "key")
        let result = try await run("ssh-keygen", ["-q"] + type.arguments + ["-C", comment, "-f", tempKey.path, "-N", passphrase])
        try check(result)
        try Self.linkNew(tempKey.path, to: url.path, linker: linker)
        do {
            try Self.linkNew(tempKey.path + ".pub", to: url.path + ".pub", linker: linker)
        } catch {
            unlink(url.path)   // our own link to the key just made
            throw error
        }
    }

    /// Leftovers of a crashed generate: `.sshcm-keygen-*` directories (this app's pattern) owned by the
    /// current user and older than `olderThan` (so a running generate is never touched). Only `key` and
    /// `key.pub` inside are deleted, then the directory itself if it is empty.
    static func removeStaleTempDirectories(in directory: URL, olderThan age: Duration) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let cutoff = Date().addingTimeInterval(-Double(age.components.seconds))
        for name in names where name.hasPrefix(".sshcm-keygen-") {
            let path = directory.appending(path: name).path
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
                  Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)) <= cutoff else { continue }
            for file in ["key", "key.pub"] {
                let filePath = path + "/" + file
                var fileInfo = stat()
                if lstat(filePath, &fileInfo) == 0, fileInfo.st_mode & S_IFMT == S_IFREG { unlink(filePath) }
            }
            rmdir(path)   // fails (harmlessly) if anything else is inside
        }
    }

    /// Puts `source` at `destination` without ever overwriting: `link(2)` (the source stays), or, on volumes
    /// without hard links, `renamex_np(RENAME_EXCL)` (the source moves). EEXIST becomes `fileExists`.
    static func linkNew(_ source: String, to destination: String,
                        linker: @Sendable (String, String) -> Int32 = { link($0, $1) }) throws {
        if linker(source, destination) == 0 { return }
        var code = errno
        if [ENOTSUP, EPERM, EXDEV, ENOSYS, EOPNOTSUPP].contains(code) {
            if renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 { return }
            code = errno
        }
        if code == EEXIST { throw KeyManagerError.fileExists(destination) }
        throw KeyManagerError.failed(String(cString: strerror(code)))
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
        if askPass.wasAsked { throw passphrase == nil ? KeyManagerError.passphraseRequired : KeyManagerError.wrongPassphrase }
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
