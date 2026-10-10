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

struct KeyFileInspectorSafetyTests {
    @Test func fifoAndDirectoryThrowInsteadOfBlocking() throws {
        let tmp = try TempDir()
        let fifo = tmp.url.appending(path: "pipe")
        #expect(Darwin.mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: (any Error).self) { try KeyFileInspector.readHead(of: fifo) }
        #expect(throws: (any Error).self) { try KeyFileInspector.readHead(of: tmp.url) }
    }

    @Test func regularFilesAndSymlinksToThemStillRead() throws {
        let tmp = try TempDir()
        let file = tmp.url.appending(path: "k")
        try Data("-----BEGIN PRIVATE KEY-----\n".utf8).write(to: file)
        let link = tmp.url.appending(path: "l")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(try KeyFileInspector.readHead(of: file).count > 0)
        #expect(try KeyFileInspector.readHead(of: link).count > 0)
    }

    @Test func procTypeIsParsedExactly() {
        func head(_ proc: String) -> Data { Data("-----BEGIN RSA PRIVATE KEY-----\n\(proc)\nMIIE\n".utf8) }
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head("Proc-Type: 4,ENCRYPTED")) == .encrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head("Proc-Type: 4, ENCRYPTED")) == .encrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head("Proc-Type: 4,MIC-ONLY")) == .unencrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head("Proc-Type: 4,NOTENCRYPTED")) == .unencrypted)
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: head("Proc-Type: 4,ENCRYPTED,extra")) == .unencrypted)
    }

    @Test func publicKeyTypeMustMatchTheBlob() async throws {
        let tmp = try TempDir()
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "c", "-f", tmp.url.appending(path: "k").path])
        let parts = try tmp.read("k.pub").split(separator: " ").map(String.init)
        #expect(PublicKeyInfo(text: "\(parts[0]) \(parts[1]) c")?.type == "ssh-ed25519")
        #expect(PublicKeyInfo(text: "ssh-rsa \(parts[1]) c") == nil)
        #expect(PublicKeyInfo(text: "bogus \(parts[1])") == nil)
        // certificates and security-key types name themselves in the blob too
        func blob(_ name: String) -> String {
            var bytes = [UInt8(0), 0, 0, UInt8(name.utf8.count)] + Array(name.utf8)
            bytes += [1, 2, 3]
            return Data(bytes).base64EncodedString()
        }
        for name in ["ssh-ed25519-cert-v01@openssh.com", "sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com"] {
            #expect(PublicKeyInfo(text: "\(name) \(blob(name))")?.type == name)
        }
    }

    @Test func commentKeepsItsSpacing() async throws {
        let tmp = try TempDir()
        _ = try await keygen(["-q", "-t", "ed25519", "-N", "", "-C", "c", "-f", tmp.url.appending(path: "k").path])
        let parts = try tmp.read("k.pub").split(separator: " ").map(String.init)
        #expect(PublicKeyInfo(text: "ssh-ed25519 \(parts[1]) my   work  key\n")?.comment == "my   work  key")
        #expect(PublicKeyInfo(text: "ssh-ed25519  \(parts[1])\t a\tb \n")?.comment == "a\tb")
        #expect(PublicKeyInfo(text: "ssh-ed25519 \(parts[1])  \n")?.comment == nil)
    }
}
