import Foundation
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
}
