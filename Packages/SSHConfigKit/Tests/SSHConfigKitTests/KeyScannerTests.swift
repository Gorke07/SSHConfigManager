import Foundation
import Synchronization
import Testing
@testable import SSHConfigKit

struct KeyScannerTests {
    /// ~/.ssh-like directory: a pair, an encrypted pair, a public-only key, a cert, config files.
    func makeDirectory(_ tmp: TempDir) async throws -> URL {
        let ssh = tmp.url.appending(path: "ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "plain", "-f", ssh.appending(path: "id_ed25519").path])
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "parola123", "-C", "locked", "-f", ssh.appending(path: "work").path])
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "pubonly", "-f", ssh.appending(path: "gone").path])
        try FileManager.default.removeItem(at: ssh.appending(path: "gone"))
        try tmp.file("ssh/config", "Host x\n")
        try tmp.file("ssh/known_hosts", "")
        try tmp.file("ssh/notes.pub", "not a key\n")
        try tmp.file("ssh/id_ed25519-cert.pub", "ssh-ed25519-cert-v01@openssh.com AAAA\n")
        return ssh
    }

    @Test func discoversPairsPublicOnlyKeysAndNothingElse() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let keys = KeyScanner.discover(directories: [ssh, ssh], extraPrivateKeys: [])
        #expect(keys.map(\.name) == ["gone.pub", "id_ed25519", "work"])
        let plain = try #require(keys.first { $0.name == "id_ed25519" })
        #expect(plain.hasPrivateKey && plain.encryption == .unencrypted && plain.publicKey?.comment == "plain")
        #expect(keys.first { $0.name == "work" }?.encryption == .encrypted)
        let pubOnly = try #require(keys.first { $0.name == "gone.pub" })
        #expect(!pubOnly.hasPrivateKey && pubOnly.encryption == .unknown && pubOnly.publicKey?.comment == "pubonly")
    }

    @Test func aPrivateKeyWithoutPubInTheDirectoryIsNotListedButAnIdentityFileOneIs() async throws {
        let tmp = try TempDir()
        let ssh = tmp.url.appending(path: "ssh")
        let elsewhere = tmp.url.appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-f", ssh.appending(path: "lonely").path])
        try FileManager.default.removeItem(at: ssh.appending(path: "lonely.pub"))
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-f", elsewhere.appending(path: "deploy").path])
        try FileManager.default.removeItem(at: elsewhere.appending(path: "deploy.pub"))
        let keys = KeyScanner.discover(directories: [ssh], extraPrivateKeys: [elsewhere.appending(path: "deploy"), tmp.url.appending(path: "missing")])
        #expect(keys.map(\.name) == ["deploy"])
        #expect(keys.first?.publicKey == nil && keys.first?.hasPrivateKey == true)
    }

    @Test func scanAddsTypeAndBitsFromSshKeygen() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let keys = await KeyScanner().scan(directories: [ssh], extraPrivateKeys: [])
        let plain = try #require(keys.first { $0.name == "id_ed25519" })
        #expect(plain.bits == 256 && plain.typeLabel == "ED25519")
    }

    struct StubRunner: ProcessRunning {
        enum Mode: Sendable { case throwing, timedOut, cancelling }
        let mode: Mode
        func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
            switch mode {
            case .throwing: throw NSError(domain: "stub", code: 1)
            case .timedOut: return ProcessResult(exitCode: 15, stdout: "", stderr: "", timedOut: true)
            case .cancelling: throw CancellationError()
            }
        }
    }

    @Test(arguments: [StubRunner.Mode.throwing, .timedOut, .cancelling])
    func scanStillReturnsKeysWhenSshKeygenFails(_ mode: StubRunner.Mode) async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let keys = await KeyScanner(runner: StubRunner(mode: mode)).scan(directories: [ssh], extraPrivateKeys: [])
        #expect(keys.map(\.name) == ["gone.pub", "id_ed25519", "work"])
        #expect(keys.allSatisfy { $0.bits == nil && $0.typeLabel == nil })
    }

    @Test func fifoWithPubBesideItIsNeverReadOrListedAsPrivate() async throws {
        let tmp = try TempDir()
        let ssh = tmp.url.appending(path: "ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "real", "-f", ssh.appending(path: "real").path])
        #expect(mkfifo(ssh.appending(path: "x").path, 0o600) == 0)
        try FileManager.default.copyItem(at: ssh.appending(path: "real.pub"), to: ssh.appending(path: "x.pub"))
        let keys = KeyScanner.discover(directories: [ssh], extraPrivateKeys: [ssh.appending(path: "x")])
        #expect(keys.first { $0.name == "x" } == nil)
        #expect(keys.first { $0.name == "real" }?.hasPrivateKey == true)
    }

    @Test func symlinkedDirectoryAlongsideItsTargetGivesNoDuplicates() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let link = tmp.url.appending(path: "ssh-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: ssh)
        let keys = KeyScanner.discover(directories: [ssh, link], extraPrivateKeys: [])
        #expect(keys.map(\.name) == ["gone.pub", "id_ed25519", "work"])
    }

    @Test func samePubReachedThroughASymlinkInASecondDirectoryIsListedOnce() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let other = tmp.url.appending(path: "other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: other.appending(path: "gone.pub"), withDestinationURL: ssh.appending(path: "gone.pub"))
        let keys = KeyScanner.discover(directories: [ssh, other], extraPrivateKeys: [])
        #expect(keys.filter { $0.name == "gone.pub" }.count == 1)
    }

    @Test func directoryNamedLikeAKeyIsListedAsPublicOnly() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        try FileManager.default.createDirectory(at: ssh.appending(path: "x"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: ssh.appending(path: "gone.pub"), to: ssh.appending(path: "x.pub"))
        let keys = KeyScanner.discover(directories: [ssh], extraPrivateKeys: [])
        let x = try #require(keys.first { $0.name == "x.pub" })
        #expect(!x.hasPrivateKey)
        #expect(keys.first { $0.name == "x" } == nil)
    }

    @Test func hiddenKeyPairsAreNotListed() async throws {
        let tmp = try TempDir()
        let ssh = tmp.url.appending(path: "ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-f", ssh.appending(path: ".secret").path])
        #expect(KeyScanner.discover(directories: [ssh], extraPrivateKeys: []).isEmpty)
    }

    @Test func publicKeyWhoseBaseIsNotAPrivateKeyIsPublicOnly() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        try tmp.file("ssh/notkey", "just some text\n")
        try FileManager.default.copyItem(at: ssh.appending(path: "gone.pub"), to: ssh.appending(path: "notkey.pub"))
        let keys = KeyScanner.discover(directories: [ssh], extraPrivateKeys: [])
        #expect(keys.first { $0.name == "notkey.pub" }?.hasPrivateKey == false)
        #expect(keys.first { $0.name == "notkey" } == nil)
    }

    @Test func publicKeyWithoutTrailingNewlineIsParsed() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let text = try String(contentsOf: ssh.appending(path: "gone.pub"), encoding: .utf8).trimmingCharacters(in: .newlines)
        try tmp.file("ssh/nonl.pub", text)
        let keys = KeyScanner.discover(directories: [ssh], extraPrivateKeys: [])
        #expect(keys.first { $0.name == "nonl.pub" }?.publicKey?.comment == "pubonly")
    }

    @Test func parsesKeygenListOutput() {
        let ed = KeyScanner.parseKeygenList("256 SHA256:abc my comment (ED25519)\n")
        #expect(ed?.bits == 256 && ed?.type == "ED25519")
        let rsa = KeyScanner.parseKeygenList("4096 SHA256:abc no comment (RSA)")
        #expect(rsa?.bits == 4096 && rsa?.type == "RSA")
        #expect(KeyScanner.parseKeygenList("garbage") == nil)
    }

    @Test(arguments: [
        ("~/.ssh/id_ed25519", "/h/.ssh/id_ed25519"),
        ("%d/.ssh/id_ed25519", "/h/.ssh/id_ed25519"),
        (".ssh/id_ed25519", "/h/.ssh/id_ed25519"),
        ("/opt/keys/k", "/opt/keys/k"),
        ("~/.ssh/../.ssh/k", "/h/.ssh/k"),
    ])
    func resolvesIdentityFileValues(_ value: String, _ expected: String) {
        #expect(KeyUsage.resolve(value, home: URL(filePath: "/h"))?.path == expected)
    }

    @Test(arguments: ["~/.ssh/id_%h", "%u/key", "~other/.ssh/k"])
    func unresolvableValuesAreNil(_ value: String) {
        #expect(KeyUsage.resolve(value, home: URL(filePath: "/h")) == nil)
    }

    @Test func hostsUsingAKeyMatchThroughSymlinksAndForms() throws {
        let tmp = try TempDir()
        let real = try tmp.file(".ssh/real_key", "x")
        try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: ".ssh/link_key"), withDestinationURL: real)
        let doc = ConfigDocument(parsing: """
        Host a
          IdentityFile ~/.ssh/real_key
        Host b c
          IdentityFile %d/.ssh/link_key
        Host d
          IdentityFile ~/.ssh/other
        Host *
          IdentityFile .ssh/real_key

        """)
        #expect(KeyUsage.hosts(using: real, in: doc.hosts, home: tmp.url) == ["a", "b c", "*"])
        // real_key, link_key (same file through the symlink) and .ssh/real_key are one file; other is the second.
        #expect(KeyUsage.identityFiles(of: doc.hosts, home: tmp.url).count == 2)
    }

    @Test func unreadablePrivateKeyIsListedAsUnreadableNotPublicOnly() async throws {
        let tmp = try TempDir()
        let ssh = tmp.url.appending(path: "ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let key = ssh.appending(path: "locked")
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "c", "-f", key.path])
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: key.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path) }
        guard access(key.path, R_OK) != 0 else { return }   // running as root: nothing is unreadable
        let keys = KeyScanner.discover(directories: [ssh], extraPrivateKeys: [])
        #expect(keys.count == 1)
        let found = try #require(keys.first)
        #expect(found.privateURL == key && found.hasPrivateKey && found.unreadable)
        #expect(found.encryption == .unknown && found.publicKey != nil)
    }

    @Test func scanDiscoversOffTheCallingThread() async throws {
        let tmp = try TempDir()
        let ssh = try await makeDirectory(tmp)
        let onMain = Mutex(Bool?.none)
        let scanner = KeyScanner(discovery: { directories, extra in
            onMain.withLock { $0 = Thread.isMainThread }
            return KeyScanner.discover(directories: directories, extraPrivateKeys: extra)
        })
        let keys = await Task { @MainActor in await scanner.scan(directories: [ssh], extraPrivateKeys: []) }.value
        #expect(onMain.withLock { $0 } == false)
        #expect(keys.map(\.name) == ["gone.pub", "id_ed25519", "work"])
    }

    @Test func fileIdentityFollowsSymlinksDotDotAndCase() throws {
        let tmp = try TempDir()
        let real = try tmp.file("a/Key", "x")
        try FileManager.default.createDirectory(at: tmp.url.appending(path: "b"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "b/link"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "dirlink"), withDestinationURL: tmp.url.appending(path: "a"))
        let other = try tmp.file("a/Other", "x")
        #expect(KeyUsage.sameFile(real, tmp.url.appending(path: "b/link")))
        #expect(KeyUsage.sameFile(real, tmp.url.appending(path: "b/../a/Key")))
        #expect(KeyUsage.sameFile(real, tmp.url.appending(path: "dirlink/Key")))
        #expect(!KeyUsage.sameFile(real, other))
        // On a case-insensitive volume (APFS default) `key` is the same file; elsewhere it does not exist.
        let lower = tmp.url.appending(path: "a/key")
        let insensitive = FileManager.default.fileExists(atPath: lower.path)
        #expect(KeyUsage.sameFile(real, lower) == insensitive)
        // Missing files fall back to the canonical path.
        #expect(KeyUsage.sameFile(tmp.url.appending(path: "nope/x"), tmp.url.appending(path: "nope/../nope/x")))
        #expect(!KeyUsage.sameFile(tmp.url.appending(path: "nope/x"), tmp.url.appending(path: "nope/y")))
    }

    @Test func discoverListsAKeyOnceThroughACaseOrSymlinkSpelling() async throws {
        let tmp = try TempDir()
        let ssh = tmp.url.appending(path: "ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-f", ssh.appending(path: "k").path])
        try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "sshlink"), withDestinationURL: ssh)
        let keys = KeyScanner.discover(directories: [ssh, tmp.url.appending(path: "sshlink"), tmp.url.appending(path: "ssh/../ssh")],
                                       extraPrivateKeys: [tmp.url.appending(path: "sshlink/k")])
        #expect(keys.map(\.name) == ["k"])
    }
}
