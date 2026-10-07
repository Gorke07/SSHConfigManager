import Foundation
import Testing
@testable import SSHConfigKit

/// Runs /usr/bin/ssh-keygen; only ever on files inside a TempDir.
func keygen(_ arguments: [String]) async throws -> ProcessResult {
    try await ProcessRunner().run(URL(filePath: "/usr/bin/ssh-keygen"), arguments: arguments, environment: [:], timeout: .seconds(60))
}

struct KeyFileInspectorTests {
    @Test(arguments: [
        (["-t", "ed25519", "-N", ""], KeyEncryption.unencrypted),
        (["-t", "ed25519", "-N", "parola123"], .encrypted),
        (["-t", "rsa", "-b", "2048", "-m", "PEM", "-N", ""], .unencrypted),
        (["-t", "rsa", "-b", "2048", "-m", "PEM", "-N", "parola123"], .encrypted),
        (["-t", "rsa", "-b", "2048", "-m", "PKCS8", "-N", ""], .unencrypted),
        (["-t", "rsa", "-b", "2048", "-m", "PKCS8", "-N", "parola123"], .encrypted),
    ])
    func detectsEncryptionFromTheHeadOnly(_ options: [String], _ expected: KeyEncryption) async throws {
        let tmp = try TempDir()
        let key = tmp.url.appending(path: "k")
        let made = try await keygen(["-q"] + options + ["-C", "c", "-f", key.path])
        #expect(made.exitCode == 0)
        let head = try KeyFileInspector.readHead(of: key)
        #expect(head.count <= KeyFileInspector.headLimit)
        #expect(KeyFileInspector.isPrivateKeyHeader(head))
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head) == expected)
    }

    @Test func publicKeyInfoMatchesSshKeygen() async throws {
        let tmp = try TempDir()
        let key = tmp.url.appending(path: "k")
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "work laptop", "-f", key.path])
        let info = try #require(PublicKeyInfo(text: try tmp.read("k.pub")))
        #expect(info.type == "ssh-ed25519")
        #expect(info.comment == "work laptop")
        let listed = try await keygen(["-lf", key.path + ".pub"])
        #expect(listed.stdout.split(separator: " ").map(String.init)[1] == info.fingerprint)
    }

    @Test func publicKeyInfoRejectsGarbage() {
        #expect(PublicKeyInfo(text: "") == nil)
        #expect(PublicKeyInfo(text: "ssh-ed25519") == nil)
        #expect(PublicKeyInfo(text: "ssh-ed25519 not*base64") == nil)
        #expect(PublicKeyInfo(text: "\n\nssh-ed25519 \(KnownHostsDocumentTests.ed)\r\n")?.comment == nil)
    }

    @Test func nonKeyFilesAreNotPrivateKeys() {
        #expect(!KeyFileInspector.isPrivateKeyHeader(Data("Host x\n".utf8)))
        #expect(!KeyFileInspector.isPrivateKeyHeader(Data("-----BEGIN CERTIFICATE-----\n".utf8)))
        #expect(!KeyFileInspector.isPrivateKeyHeader(Data()))
        #expect(KeyFileInspector.isPrivateKeyHeader(Data("-----BEGIN OPENSSH PRIVATE KEY-----\r\n".utf8)))
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Data("Host x\n".utf8)) == .unknown)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Data("-----BEGIN OPENSSH PRIVATE KEY-----\n".utf8)) == .unknown)
    }

    @Test func readsAtMostTheHeadLimit() throws {
        let tmp = try TempDir()
        let file = try tmp.file("big", String(repeating: "A", count: 10_000))
        #expect(try KeyFileInspector.readHead(of: file).count == KeyFileInspector.headLimit)
    }
}
