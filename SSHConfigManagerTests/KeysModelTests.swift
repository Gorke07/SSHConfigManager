import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct KeysModelTests {
    @Test func refreshListsKeysWithUsageAndAgentUnknown() async throws {
        let tmp = try TempDir()
        let actions = RecordingKeyActions()
        let model = makeTestModel(tmp, config: "Host web\n  IdentityFile ~/.ssh/id_ed25519\nHost *\n  User me\n", keyActions: actions)
        _ = await model.keys.generate(type: .ed25519, fileName: "id_ed25519", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first { $0.key.name == "id_ed25519" })
        #expect(row.usedBy == ["web"])
        #expect(row.inAgent == nil)                 // makeTestModel uses an unreachable agent socket
        #expect(row.displayPath == "~/.ssh/id_ed25519")
        #expect(row.key.encryption == .unencrypted)
    }

    @Test func suggestedNamesNeverCollide() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        #expect(model.keys.suggestedFileName(for: .ed25519) == "id_ed25519")
        _ = await model.keys.generate(type: .ed25519, fileName: "id_ed25519", comment: "c", passphrase: "", assignTo: nil)
        #expect(model.keys.suggestedFileName(for: .ed25519) == "id_ed25519_2")
        #expect(model.keys.suggestedFileName(for: .rsa) == "id_rsa")
    }

    @Test func generateRefusesExistingFilesAndBadNames() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        try tmp.file(".ssh/taken.pub", "keep\n")
        #expect(await model.keys.generate(type: .ed25519, fileName: "taken", comment: "c", passphrase: "", assignTo: nil) == false)
        #expect(try tmp.read(".ssh/taken.pub") == "keep\n")
        #expect(model.keys.errorMessage?.isEmpty == false)
        for bad in ["", "../x", "a/b", ".hidden"] {
            #expect(await model.keys.generate(type: .ed25519, fileName: bad, comment: "c", passphrase: "", assignTo: nil) == false)
            #expect(model.keys.errorMessage == String(localized: "keys.error.invalidFileName"))
        }
    }

    @Test func generateCanAssignTheKeyToAHostAsAnUnsavedEdit() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  HostName 10.0.0.1\n")
        #expect(model.assignableAliases == ["web"])
        #expect(await model.keys.generate(type: .ed25519, fileName: "deploy", comment: "c", passphrase: "", assignTo: "web"))
        #expect(model.store.hasUnsavedChanges)
        #expect(model.store.document.hosts.first?.values(for: "IdentityFile") == ["~/.ssh/deploy"])
        #expect(try tmp.read(".ssh/config") == "Host web\n  HostName 10.0.0.1\n")   // saved only through the Save flow
    }

    @Test func copyAndTrashUseTheInjectedActions() async throws {
        let tmp = try TempDir()
        let actions = RecordingKeyActions()
        let model = makeTestModel(tmp, config: "Host web\n", keyActions: actions)
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first)
        model.keys.copyPublicKey(row)
        #expect(actions.copied.first?.hasPrefix("ssh-ed25519 ") == true)
        #expect(actions.copied.first?.hasSuffix("\n") == false)
        #expect(await model.keys.trash(row))
        #expect(actions.recycled == [[row.key.privateURL!, row.key.publicURL!]])
    }

    @Test func wrongPassphraseAndNoAgentAreReportedNotThrown() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "parola123", assignTo: nil)
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first)
        #expect(await model.keys.addToAgent(row, passphrase: "parola123") == false)
        #expect(model.keys.errorMessage == String(localized: "keys.error.noAgent"))
        #expect(await model.keys.changePassphrase(row, old: "yanlis123", new: "") == false)
        #expect(model.keys.errorMessage == String(localized: "keys.error.wrongPassphrase"))
        #expect(await model.keys.changePassphrase(row, old: "parola123", new: ""))
    }
}
