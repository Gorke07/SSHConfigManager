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

    @Test func publicKeyInfoRejectsGarbage() throws {
        #expect(PublicKeyInfo(text: "") == nil)
        #expect(PublicKeyInfo(text: "ssh-ed25519") == nil)
        #expect(PublicKeyInfo(text: "ssh-ed25519 not*base64") == nil)
        let info = try #require(PublicKeyInfo(text: "\n\nssh-ed25519 \(KnownHostsDocumentTests.ed)\r\n"))
        #expect(info.type == "ssh-ed25519")
        #expect(info.comment == nil)
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

    private static let magic = Array("openssh-key-v1".utf8) + [0]

    private static func openSSHHead(_ bytes: [UInt8]) -> Data {
        Data("-----BEGIN OPENSSH PRIVATE KEY-----\n\(Data(bytes).base64EncodedString())\n".utf8)
    }

    @Test func wellFormedOpenSSHHeadsAreRecognized() {
        let none = Self.magic + [0, 0, 0, 4] + Array("none".utf8)
        let aes = Self.magic + [0, 0, 0, 10] + Array("aes256-ctr".utf8)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Self.openSSHHead(none)) == .unencrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Self.openSSHHead(aes)) == .encrypted)
    }

    @Test func malformedOpenSSHHeadsAreUnknown() {
        let header = "-----BEGIN OPENSSH PRIVATE KEY-----\n"
        let cases: [Data] = [
            Data((header + "!!!!not*base64!!\n").utf8),
            Self.openSSHHead(Array("openss".utf8)),
            Self.openSSHHead(Array("wrong-magic-v1".utf8) + [0, 0, 0, 0, 4] + Array("none".utf8)),
            Self.openSSHHead(Self.magic + [0, 0, 0, 0] + Array("none".utf8)),
            Self.openSSHHead(Self.magic + [0x7F, 0xFF, 0xFF, 0xFF] + Array("none".utf8)),
            Self.openSSHHead(Self.magic + [0xFF, 0xFF, 0xFF, 0xFF] + Array("none".utf8)),
            Self.openSSHHead(Self.magic + [0, 0, 0, 4] + Array("no".utf8)),
            Self.openSSHHead(Self.magic + [0, 0]),
            Data(header.utf8),
        ]
        for head in cases {
            #expect(KeyFileInspector.isPrivateKeyHeader(head))
            #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head) == .unknown)
        }
    }

    @Test func crlfPEMHeadsAreDetected() {
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Data("-----BEGIN RSA PRIVATE KEY-----\r\nProc-Type: 4,ENCRYPTED\r\n".utf8)) == .encrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Data("-----BEGIN ENCRYPTED PRIVATE KEY-----\r\n".utf8)) == .encrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: Data("-----BEGIN RSA PRIVATE KEY-----\r\nMIIE\r\n".utf8)) == .unencrypted)
    }
}
