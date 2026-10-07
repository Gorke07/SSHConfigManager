import Foundation

public struct ResolvedHost: Equatable, Sendable {
    public let hostname: String
    public let port: Int
    public let hostKeyAlias: String?

    public init(hostname: String, port: Int, hostKeyAlias: String?) {
        self.hostname = hostname
        self.port = port
        self.hostKeyAlias = hostKeyAlias
    }

    /// Names to look up in known_hosts: the HostKeyAlias as written (ssh uses it instead of the
    /// host name, without a port) and the host name in ssh's `host` / `[host]:port` form.
    public var lookupNames: [String] {
        var names: [String] = []
        if let hostKeyAlias { names.append(hostKeyAlias) }
        names.append(HostMatcher.lookupName(host: hostname, port: port))
        return names
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
        } catch {
            throw HostResolverError.failed(error.localizedDescription)
        }
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
            if values[key] == nil { values[key] = String(parts[1]) }
        }
        guard let hostname = values["hostname"], !hostname.isEmpty,
              let port = Int(values["port"] ?? "22"), (1...65535).contains(port) else { return nil }
        let alias = values["hostkeyalias"].flatMap { $0.isEmpty || $0 == "none" ? nil : $0 }
        return ResolvedHost(hostname: hostname, port: port, hostKeyAlias: alias)
    }
}
