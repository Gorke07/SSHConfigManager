import Foundation

public struct SSHKey: Identifiable, Equatable, Sendable {
    public let privateURL: URL?
    public let publicURL: URL?
    public let publicKey: PublicKeyInfo?
    public let encryption: KeyEncryption
    /// The private key exists but could not be read (permissions, I/O): its encryption is unknown.
    public let unreadable: Bool
    /// From `ssh-keygen -lf` on the public key.
    public var bits: Int?
    public var typeLabel: String?

    public init(privateURL: URL?, publicURL: URL?, publicKey: PublicKeyInfo?, encryption: KeyEncryption, unreadable: Bool = false, bits: Int? = nil, typeLabel: String? = nil) {
        self.privateURL = privateURL
        self.publicURL = publicURL
        self.publicKey = publicKey
        self.encryption = encryption
        self.unreadable = unreadable
        self.bits = bits
        self.typeLabel = typeLabel
    }

    /// The private key, or the `.pub` file for a public-only key.
    public var fileURL: URL { privateURL ?? publicURL ?? URL(filePath: "/") }
    public var id: String { fileURL.path }
    public var name: String { fileURL.lastPathComponent }
    public var hasPrivateKey: Bool { privateURL != nil }
}

/// Finds keys (spec §8.1): a private key is a file whose head is a `-----BEGIN … PRIVATE KEY-----`
/// header and that has a `<name>.pub` beside it; a `.pub` alone is listed as a public-only key.
/// IdentityFile targets outside the scanned directories are added even without a `.pub`.
public struct KeyScanner: Sendable {
    private let runner: any ProcessRunning
    private let sshKeygen: URL
    private let discovery: @Sendable ([URL], [URL]) -> [SSHKey]

    /// `discovery` is a test seam; it always runs off the calling actor.
    public init(runner: any ProcessRunning = ProcessRunner(), sshKeygen: URL = URL(filePath: "/usr/bin/ssh-keygen"),
                discovery: @escaping @Sendable ([URL], [URL]) -> [SSHKey] = { KeyScanner.discover(directories: $0, extraPrivateKeys: $1) }) {
        self.runner = runner
        self.sshKeygen = sshKeygen
        self.discovery = discovery
    }

    public func scan(directories: [URL], extraPrivateKeys: [URL] = []) async -> [SSHKey] {
        // File I/O must not run on the caller's (main) actor.
        let discovery = discovery
        var keys = await Task.detached(priority: .userInitiated) { discovery(directories, extraPrivateKeys) }.value
        for index in keys.indices {
            // Stop on cancellation: no more processes, return what we have.
            if Task.isCancelled { break }
            guard let pub = keys[index].publicURL else { continue }
            let result: ProcessResult
            do {
                result = try await runner.run(sshKeygen, arguments: ["-lf", pub.path], environment: [:], timeout: .seconds(5))
            } catch is CancellationError {
                break
            } catch {
                continue
            }
            guard result.exitCode == 0, !result.timedOut, let described = Self.parseKeygenList(result.stdout) else { continue }
            keys[index].bits = described.bits
            keys[index].typeLabel = described.type
        }
        return keys
    }

    public static func discover(directories: [URL], extraPrivateKeys: [URL]) -> [SSHKey] {
        let fm = FileManager.default
        var seenDirectories = Set<String>()
        var seenFiles = Set<String>()
        var keys: [SSHKey] = []

        /// A regular file after following symlinks: never a FIFO, device, socket or directory,
        /// which could block or misbehave when read.
        func isFile(_ url: URL) -> Bool {
            let resolved = url.resolvingSymlinksInPath()
            return (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
        func publicInfo(_ url: URL) -> PublicKeyInfo? {
            (try? String(contentsOf: url, encoding: .utf8)).flatMap(PublicKeyInfo.init(text:))
        }
        func addPrivate(_ url: URL) {
            let identity = KeyUsage.identity(url)
            guard !seenFiles.contains(identity), isFile(url) else { return }
            let head: Data
            do {
                head = try KeyFileInspector.readHead(of: url)
            } catch let error as POSIXError where ![.ENOENT, .ENOTDIR, .ELOOP].contains(error.code) {
                // It exists and is a file but cannot be read: show it as an unreadable private key
                // (never as a public-only key beside it).
                seenFiles.insert(identity)
                let pub = URL(filePath: url.path + ".pub")
                let info = publicInfo(pub)
                keys.append(SSHKey(privateURL: url, publicURL: info == nil ? nil : pub, publicKey: info,
                                   encryption: .unknown, unreadable: true))
                return
            } catch {
                return
            }
            guard KeyFileInspector.isPrivateKeyHeader(head) else { return }
            seenFiles.insert(identity)
            let pub = URL(filePath: url.path + ".pub")
            let info = publicInfo(pub)
            keys.append(SSHKey(privateURL: url, publicURL: info == nil ? nil : pub, publicKey: info,
                               encryption: KeyFileInspector.encryption(ofPrivateKeyHead: head)))
        }

        for directory in directories {
            guard seenDirectories.insert(KeyUsage.identity(directory)).inserted,
                  let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            let visible = names.filter { !$0.hasPrefix(".") }.sorted()
            let visibleSet = Set(visible)
            for name in visible where !name.hasSuffix(".pub") && visibleSet.contains(name + ".pub") {
                addPrivate(directory.appending(path: name))
            }
            for name in visible where name.hasSuffix(".pub") && !name.hasSuffix("-cert.pub") {
                let pub = directory.appending(path: name)
                let base = URL(filePath: String(pub.path.dropLast(4)))
                let pubIdentity = KeyUsage.identity(pub)
                guard !seenFiles.contains(KeyUsage.identity(base)), !seenFiles.contains(pubIdentity),
                      isFile(pub), let info = publicInfo(pub) else { continue }
                seenFiles.insert(pubIdentity)
                keys.append(SSHKey(privateURL: nil, publicURL: pub, publicKey: info, encryption: .unknown))
            }
        }
        for url in extraPrivateKeys { addPrivate(url) }
        return keys.sorted {
            if $0.name != $1.name { return $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
            return $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
        }
    }

    /// `256 SHA256:… comment (ED25519)` → (256, "ED25519").
    public static func parseKeygenList(_ output: String) -> (bits: Int, type: String)? {
        guard let line = output.split(whereSeparator: \.isNewline).first else { return nil }
        let parts = line.split(separator: " ")
        guard let first = parts.first, let bits = Int(first), let last = parts.last,
              last.hasPrefix("("), last.hasSuffix(")"), last.count > 2 else { return nil }
        return (bits, String(last.dropFirst().dropLast()))
    }
}
