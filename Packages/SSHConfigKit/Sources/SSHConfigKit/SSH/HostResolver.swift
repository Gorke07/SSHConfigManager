import Foundation

public struct ResolvedHost: Equatable, Sendable {
    public let hostname: String
    public let port: Int
    public let hostKeyAlias: String?
    /// `CheckHostIP yes`: ssh also keeps and checks an entry for the host's IP address.
    public let checkHostIP: Bool
    /// The `UserKnownHostsFile` paths, split like config arguments (quotes honoured). `ssh -G` prints the
    /// value space-separated, paths already expanded and unquoted, so a path with spaces is split here:
    /// compare with `userKnownHostsFileCandidates`, not just this list.
    public let userKnownHostsFiles: [String]

    /// Every way the printed value can be cut into paths: each token, and each run of adjacent tokens
    /// joined by single spaces (the whole value included). A path with spaces is among them.
    public var userKnownHostsFileCandidates: [String] {
        var result: [String] = []
        let tokens = userKnownHostsFiles
        for start in tokens.indices {
            for end in start..<tokens.count {
                let joined = tokens[start...end].joined(separator: " ")
                if !result.contains(joined) { result.append(joined) }
            }
        }
        return result
    }

    public init(hostname: String, port: Int, hostKeyAlias: String?, checkHostIP: Bool = false, userKnownHostsFiles: [String] = []) {
        self.hostname = hostname
        self.port = port
        self.hostKeyAlias = hostKeyAlias
        self.checkHostIP = checkHostIP
        self.userKnownHostsFiles = userKnownHostsFiles
    }

    /// The name ssh looks up in known_hosts, in its `host` / `[host]:port` form. With a HostKeyAlias ssh
    /// uses the alias INSTEAD of the host name (same port bracketing), never both.
    public var lookupNames: [String] {
        [HostMatcher.lookupName(host: hostKeyAlias ?? hostname, port: port)]
    }
}

public enum HostResolverError: Error, Equatable, Sendable {
    /// ssh's first stderr line (English, untranslated by design).
    case failed(String)
    case timedOut
    case unparsable
}

/// Asks `ssh -G` which host name, port and HostKeyAlias an alias really uses.
public struct HostResolver: Sendable {
    private let commandBuilder: SSHCommandBuilder
    private let runner: any ProcessRunning
    private let sshPath: URL

    public init(commandBuilder: SSHCommandBuilder, runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")) {
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.sshPath = sshPath
    }

    public func resolve(alias: String) async throws -> ResolvedHost {
        let arguments = commandBuilder.sshArguments(options: ["-G"], alias: alias)
        let result: ProcessResult
        do {
            result = try await runner.run(sshPath, arguments: arguments, environment: [:], timeout: .seconds(5))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HostResolverError.failed(error.localizedDescription)
        }
        // Cancelled: a signalled ssh reports a failure that nobody wants to see.
        try Task.checkCancellation()
        if result.timedOut { throw HostResolverError.timedOut }
        guard result.exitCode == 0 else { throw HostResolverError.failed(ConnectionClassifier.firstLine(result.stderr)) }
        guard let host = Self.parse(result.stdout) else { throw HostResolverError.unparsable }
        return host
    }

    /// `ssh -G` prints one lowercase option name and its value per line.
    public static func parse(_ output: String) -> ResolvedHost? {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            if values[key] == nil { values[key] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        guard let hostname = values["hostname"], !hostname.isEmpty,
              let port = Int(values["port"] ?? "22"), (1...65535).contains(port) else { return nil }
        let alias = values["hostkeyalias"].flatMap { $0.isEmpty || $0 == "none" ? nil : $0 }
        let checkHostIP = values["checkhostip"]?.asciiLowercased == "yes"
        let files = LineTokenizer.arguments(of: values["userknownhostsfile"] ?? "")
        return ResolvedHost(hostname: hostname, port: port, hostKeyAlias: alias, checkHostIP: checkHostIP, userKnownHostsFiles: files)
    }
}
