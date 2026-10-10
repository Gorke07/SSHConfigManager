import Foundation
import Testing
@testable import SSHConfigKit

struct KeyManagerTests {
    /// Never the user's agent: an unreachable socket unless a TestAgent is given.
    func manager(_ tmp: TempDir, agent: TestAgent? = nil) -> KeyManager {
        KeyManager(agentSocket: agent?.socket ?? "/tmp/sshcm-none-\(UUID().uuidString.prefix(8))", askPassDirectory: tmp.url)
    }

    func askPassLeftovers(_ tmp: TempDir) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).filter { $0.hasPrefix("sshcm-askpass-") }
    }

    @Test func generatesAnEd25519KeyWithoutPassphrase() async throws {
        let tmp = try TempDir()
        let url = tmp.url.appending(path: "keys/id_ed25519")
        try await manager(tmp).generate(type: .ed25519, at: url, comment: "me@mac", passphrase: "")
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: try KeyFileInspector.readHead(of: url)) == .unencrypted)
        #expect(PublicKeyInfo(text: try tmp.read("keys/id_ed25519.pub"))?.comment == "me@mac")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let pubMode = try FileManager.default.attributesOfItem(atPath: url.path + ".pub")[.posixPermissions] as? Int
        #expect(pubMode == 0o644)
        let dirMode = try FileManager.default.attributesOfItem(atPath: tmp.url.appending(path: "keys").path)[.posixPermissions] as? Int
        #expect(dirMode == 0o700)
    }

    @Test func generatesAnEncryptedRSA4096Key() async throws {
        let tmp = try TempDir()
        let url = tmp.url.appending(path: "id_rsa")
        try await manager(tmp).generate(type: .rsa, at: url, comment: "c", passphrase: "parola123")
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: try KeyFileInspector.readHead(of: url)) == .encrypted)
        let keys = await KeyScanner().scan(directories: [tmp.url], extraPrivateKeys: [])
        #expect(keys.first?.bits == 4096)
    }

    @Test func neverOverwritesAndRejectsShortPassphrases() async throws {
        let tmp = try TempDir()
        let existing = try tmp.file("id_ed25519.pub", "keep me\n")
        await #expect(throws: KeyManagerError.fileExists(existing.path)) {
            try await manager(tmp).generate(type: .ed25519, at: tmp.url.appending(path: "id_ed25519"), comment: "c", passphrase: "")
        }
        #expect(try tmp.read("id_ed25519.pub") == "keep me\n")
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: "id_ed25519").path))
        await #expect(throws: KeyManagerError.passphraseTooShort) {
            try await manager(tmp).generate(type: .ed25519, at: tmp.url.appending(path: "k"), comment: "c", passphrase: "abcd")
        }
        #expect(KeyManager.isValidPassphrase("") && KeyManager.isValidPassphrase("abcde") && !KeyManager.isValidPassphrase("abcd"))
    }

    @Test func passphrasesWithLineBreaksAreRejected() async throws {
        let tmp = try TempDir()
        for bad in ["abcde\nfghij", "abcde\rfghij", "abcde\r\nfghij"] {
            #expect(!KeyManager.isValidPassphrase(bad))
            await #expect(throws: KeyManagerError.invalidPassphrase) {
                try await manager(tmp).generate(type: .ed25519, at: tmp.url.appending(path: "k"), comment: "c", passphrase: bad)
            }
            await #expect(throws: KeyManagerError.invalidPassphrase) {
                try await manager(tmp).changePassphrase(at: tmp.url.appending(path: "k"), old: "", new: bad)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: "k").path))
        #expect(KeyManager.isValidPassphrase("with space and tab\t"))
    }

    @Test func nextAvailableNameSkipsPrivateAndPublicFiles() throws {
        let tmp = try TempDir()
        #expect(KeyManager.nextAvailableURL(fileName: "id_ed25519", in: tmp.url).lastPathComponent == "id_ed25519")
        try tmp.file("id_ed25519.pub", "x")
        #expect(KeyManager.nextAvailableURL(fileName: "id_ed25519", in: tmp.url).lastPathComponent == "id_ed25519_2")
        try tmp.file("id_ed25519_2", "x")
        #expect(KeyManager.nextAvailableURL(fileName: "id_ed25519", in: tmp.url).lastPathComponent == "id_ed25519_3")
    }

    @Test func changesThePassphraseAndReportsAWrongOne() async throws {
        let tmp = try TempDir()
        let url = tmp.url.appending(path: "k")
        let keys = manager(tmp)
        try await keys.generate(type: .ed25519, at: url, comment: "c", passphrase: "eski12345")
        await #expect(throws: KeyManagerError.wrongPassphrase) {
            try await keys.changePassphrase(at: url, old: "yanlis123", new: "yeni12345")
        }
        try await keys.changePassphrase(at: url, old: "eski12345", new: "")
        #expect(KeyFileInspector.encryption(ofPrivateKeyHead: try KeyFileInspector.readHead(of: url)) == .unencrypted)
    }

    @Test func addsToAPrivateAgentAndNeverHangsOnAWrongPassphrase() async throws {
        let tmp = try TempDir()
        let agent = try TestAgent()
        let keys = manager(tmp, agent: agent)
        let url = tmp.url.appending(path: "k")
        try await keys.generate(type: .ed25519, at: url, comment: "c", passphrase: "dogru1234")
        #expect(await keys.agentFingerprints() == [])

        let started = ContinuousClock.now
        await #expect(throws: KeyManagerError.wrongPassphrase) {
            try await keys.addToAgent(url, passphrase: "yanlis123", useKeychain: false)
        }
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(try askPassLeftovers(tmp).isEmpty)

        try await keys.addToAgent(url, passphrase: "dogru1234", useKeychain: false)
        let fingerprint = try #require(PublicKeyInfo(text: try tmp.read("k.pub"))?.fingerprint)
        #expect(await keys.agentFingerprints() == [fingerprint])
        #expect(try askPassLeftovers(tmp).isEmpty)
    }

    @Test func unencryptedKeysNeedNoPassphrase() async throws {
        let tmp = try TempDir()
        let agent = try TestAgent()
        let keys = manager(tmp, agent: agent)
        let url = tmp.url.appending(path: "k")
        try await keys.generate(type: .ed25519, at: url, comment: "c", passphrase: "")
        try await keys.addToAgent(url, passphrase: nil, useKeychain: false)
        #expect(await keys.agentFingerprints()?.count == 1)
    }

    @Test func noAgentIsReported() async throws {
        let tmp = try TempDir()
        let keys = manager(tmp)
        let url = tmp.url.appending(path: "k")
        try await keys.generate(type: .ed25519, at: url, comment: "c", passphrase: "")
        #expect(await keys.agentFingerprints() == nil)
        await #expect(throws: KeyManagerError.noAgent) { try await keys.addToAgent(url, passphrase: nil, useKeychain: false) }
    }

    @Test func parsesAgentListings() {
        let output = "256 SHA256:aaa c (ED25519)\n4096 SHA256:bbb other comment (RSA)\n"
        #expect(KeyManager.parseAgentList(output) == ["SHA256:aaa", "SHA256:bbb"])
        #expect(KeyManager.parseAgentList("") == [])
    }

    @Test func generateNeverOverwritesALateAppearingPublicFile() throws {
        // The final paths are only ever created by link(2), which fails if either exists.
        let tmp = try TempDir()
        let existing = try tmp.file("k.pub", "mine\n")
        let source = try tmp.file("src", "new\n")
        #expect(throws: KeyManagerError.fileExists(existing.path)) {
            try KeyManager.linkNew(source.path, to: existing.path)
        }
        #expect(try tmp.read("k.pub") == "mine\n")
    }

    @Test func generateLeavesNoTempDirectoryAndKeepsModes() async throws {
        let tmp = try TempDir()
        try await manager(tmp).generate(type: .ed25519, at: tmp.url.appending(path: "k"), comment: "c", passphrase: "")
        let names = try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).sorted()
        #expect(names == ["k", "k.pub"])
        let mode = try FileManager.default.attributesOfItem(atPath: tmp.url.appending(path: "k").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func generateRefusesWhenOnlyThePublicFileAppearedMeanwhile() async throws {
        let tmp = try TempDir()
        let danglingPub = tmp.url.appending(path: "k.pub")
        try FileManager.default.createSymbolicLink(at: danglingPub, withDestinationURL: tmp.url.appending(path: "nowhere"))
        // fileExists follows the dangling link, so the pre-check passes; link(2) must still refuse.
        await #expect(throws: KeyManagerError.fileExists(danglingPub.path)) {
            try await manager(tmp).generate(type: .ed25519, at: tmp.url.appending(path: "k"), comment: "c", passphrase: "")
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: "k").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).sorted() == ["k.pub"])
    }

    @Test func askPassIsRemovedWhenSetupFails() throws {
        let tmp = try TempDir()
        // A parent that is a file makes createDirectory fail before anything exists; nothing may be left.
        let file = try tmp.file("parent", "x")
        #expect(throws: (any Error).self) { try AskPass.make(in: file) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path) == ["parent"])
    }

    @Test func anEncryptedKeyWithNoPassphraseAsksForOne() async throws {
        let tmp = try TempDir()
        let agent = try TestAgent()
        let keys = manager(tmp, agent: agent)
        let url = tmp.url.appending(path: "k")
        try await keys.generate(type: .ed25519, at: url, comment: "c", passphrase: "dogru1234")
        await #expect(throws: KeyManagerError.passphraseRequired) {
            try await keys.addToAgent(url, passphrase: nil, useKeychain: false)
        }
        await #expect(throws: KeyManagerError.wrongPassphrase) {
            try await keys.addToAgent(url, passphrase: "yanlis123", useKeychain: false)
        }
        #expect(try askPassLeftovers(tmp).isEmpty)
    }

    /// A linker that always fails like a volume without hard links.
    private static let noHardLinks: @Sendable (String, String) -> Int32 = { _, _ in errno = ENOTSUP; return -1 }

    @Test func generateFallsBackToExclusiveRenameWithoutHardLinks() async throws {
        let tmp = try TempDir()
        var keys = manager(tmp)
        keys.linker = Self.noHardLinks
        let url = tmp.url.appending(path: "k")
        try await keys.generate(type: .ed25519, at: url, comment: "c", passphrase: "")
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).sorted() == ["k", "k.pub"])
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(PublicKeyInfo(text: try tmp.read("k.pub"))?.comment == "c")
    }

    @Test func theRenameFallbackNeverOverwritesAndMapsErrors() throws {
        let tmp = try TempDir()
        let existing = try tmp.file("dst", "mine\n")
        let source = try tmp.file("src", "new\n")
        #expect(throws: KeyManagerError.fileExists(existing.path)) {
            try KeyManager.linkNew(source.path, to: existing.path, linker: Self.noHardLinks)
        }
        #expect(try tmp.read("dst") == "mine\n")
        #expect(try tmp.read("src") == "new\n")
        let fresh = tmp.url.appending(path: "fresh").path
        try KeyManager.linkNew(source.path, to: fresh, linker: Self.noHardLinks)
        #expect(try tmp.read("fresh") == "new\n")
        #expect(throws: KeyManagerError.self) {
            try KeyManager.linkNew(tmp.url.appending(path: "missing").path, to: tmp.url.appending(path: "x").path, linker: Self.noHardLinks)
        }
    }

    @Test func staleKeygenDirectoriesAreRemovedButOnlyOurPatternAndOnlyKeyFiles() throws {
        let tmp = try TempDir()
        let fm = FileManager.default
        let stale = try tmp.file(".sshcm-keygen-OLD/key", "secret")
        try tmp.file(".sshcm-keygen-OLD/key.pub", "pub")
        try tmp.file(".sshcm-keygen-OTHER/key", "secret")
        try tmp.file(".sshcm-keygen-OTHER/precious.txt", "keep")
        try tmp.file(".other-dir/key", "keep")
        try tmp.file(".sshcm-keygen-file", "keep")
        let target = try tmp.file("target-secret", "keep")
        try fm.createSymbolicLink(at: tmp.url.appending(path: ".sshcm-keygen-LINK"), withDestinationURL: tmp.url.appending(path: ".other-dir"))
        _ = target
        // A fresh directory (a generate in flight) is left alone with a positive age.
        KeyManager.removeStaleTempDirectories(in: tmp.url, olderThan: .seconds(3600))
        #expect(fm.fileExists(atPath: stale.path))
        KeyManager.removeStaleTempDirectories(in: tmp.url, olderThan: .zero)
        #expect(!fm.fileExists(atPath: tmp.url.appending(path: ".sshcm-keygen-OLD").path))
        #expect(!fm.fileExists(atPath: tmp.url.appending(path: ".sshcm-keygen-OTHER/key").path))
        #expect(try tmp.read(".sshcm-keygen-OTHER/precious.txt") == "keep")   // only key/key.pub, so the dir stays
        #expect(try tmp.read(".other-dir/key") == "keep")                      // the symlink was not followed
        #expect(try tmp.read(".sshcm-keygen-file") == "keep")
    }

    @Test func generateClearsStaleLeftoversFirst() async throws {
        let tmp = try TempDir()
        let leftover = try tmp.file(".sshcm-keygen-CRASHED/key", "secret")
        // Backdate it past the 5 minute window generate uses.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                              ofItemAtPath: leftover.deletingLastPathComponent().path)
        try await manager(tmp).generate(type: .ed25519, at: tmp.url.appending(path: "k"), comment: "c", passphrase: "")
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).sorted() == ["k", "k.pub"])
    }
}
