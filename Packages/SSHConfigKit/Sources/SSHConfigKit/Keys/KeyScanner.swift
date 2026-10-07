import Foundation

public struct SSHKey: Identifiable, Equatable, Sendable {
    public let privateURL: URL?
    public let publicURL: URL?
    public let publicKey: PublicKeyInfo?
    public let encryption: KeyEncryption
    /// From `ssh-keygen -lf` on the public key.
    public var bits: Int?
    public var typeLabel: String?

    public init(privateURL: URL?, publicURL: URL?, publicKey: PublicKeyInfo?, encryption: KeyEncryption, bits: Int? = nil, typeLabel: String? = nil) {
        self.privateURL = privateURL
        self.publicURL = publicURL
        self.publicKey = publicKey
        self.encryption = encryption
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

    public init(runner: any ProcessRunning = ProcessRunner(), sshKeygen: URL = URL(filePath: "/usr/bin/ssh-keygen")) {
        self.runner = runner
        self.sshKeygen = sshKeygen
    }

    public func scan(directories: [URL], extraPrivateKeys: [URL] = []) async -> [SSHKey] {
        var keys = Self.discover(directories: directories, extraPrivateKeys: extraPrivateKeys)
        for index in keys.indices {
            guard let pub = keys[index].publicURL,
                  let result = try? await runner.run(sshKeygen, arguments: ["-lf", pub.path], environment: [:], timeout: .seconds(30)),
                  result.exitCode == 0, let described = Self.parseKeygenList(result.stdout) else { continue }
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

        func isFile(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        func publicInfo(_ url: URL) -> PublicKeyInfo? {
            (try? String(contentsOf: url, encoding: .utf8)).flatMap(PublicKeyInfo.init(text:))
        }
        func addPrivate(_ url: URL) {
            let canonical = KeyUsage.canonicalPath(url)
            guard !seenFiles.contains(canonical), isFile(url),
                  let head = try? KeyFileInspector.readHead(of: url), KeyFileInspector.isPrivateKeyHeader(head) else { return }
            seenFiles.insert(canonical)
            let pub = URL(filePath: url.path + ".pub")
            let info = publicInfo(pub)
            keys.append(SSHKey(privateURL: url, publicURL: info == nil ? nil : pub, publicKey: info,
                               encryption: KeyFileInspector.encryption(ofPrivateKeyHead: head)))
        }

        for directory in directories {
            guard seenDirectories.insert(KeyUsage.canonicalPath(directory)).inserted,
                  let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            let visible = names.filter { !$0.hasPrefix(".") }.sorted()
            for name in visible where !name.hasSuffix(".pub") && visible.contains(name + ".pub") {
                addPrivate(directory.appending(path: name))
            }
            for name in visible where name.hasSuffix(".pub") && !name.hasSuffix("-cert.pub") {
                let pub = directory.appending(path: name)
                let base = URL(filePath: String(pub.path.dropLast(4)))
                guard !seenFiles.contains(KeyUsage.canonicalPath(base)), isFile(pub), let info = publicInfo(pub) else { continue }
                seenFiles.insert(KeyUsage.canonicalPath(pub))
                keys.append(SSHKey(privateURL: nil, publicURL: pub, publicKey: info, encryption: .unknown))
            }
        }
        for url in extraPrivateKeys { addPrivate(url) }
        return keys.sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
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
