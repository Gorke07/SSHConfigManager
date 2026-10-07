import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct SaveFlowModelTests {
    private func addPort(_ app: AppModel) throws {
        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "Port", value: "2222"))
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
    }

    @Test func reviewThenSave() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        #expect(flow.phase == .preparing)

        await flow.prepare()
        guard case .review(let preparation) = flow.phase else { Issue.record("review bekleniyordu"); return }
        #expect(preparation.validation == .valid)
        #expect(preparation.hunks.count == 1)
        #expect(flow.canConfirm)

        await flow.confirm()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n")
    }

    @Test func invalidConfigCannotBeConfirmed() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n", runner: .invalid("line 2: Bad configuration option: bogus"))
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        #expect(!flow.canConfirm)
        await flow.confirm()   // ignored while not confirmable
        #expect(try tmp.read(".ssh/config") == "Host a\n")
    }

    @Test func conflictOffersOverwriteOrDiskVersion() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)
        #expect(!flow.conflictHunks().isEmpty)

        await flow.overwrite()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n")
    }

    @Test func loadDiskVersionDiscardsMine() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        flow.loadDiskVersion()
        #expect(flow.phase == .done)
        #expect(app.store.document.render() == "Host a\n  User vim\n")
        #expect(!app.store.hasUnsavedChanges)
    }

    @Test func failuresBecomeMessages() async throws {
        let tmp = try TempDir()
        try tmp.file("Backups", "not a directory")   // backup root is a file → backup fails
        let app = makeTestModel(tmp, config: "Host a\n")
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        guard case .failed(let message) = flow.phase else { Issue.record("failed bekleniyordu: \(flow.phase)"); return }
        let template = Messages.text(for: ConfigStoreError.writeFailed(.backupFailed("§")))
        let fixedPart = try #require(template.components(separatedBy: "§").first)
        #expect(!fixedPart.isEmpty)
        #expect(message.hasPrefix(fixedPart))
        #expect(try tmp.read(".ssh/config") == "Host a\n")
    }

    @Test func overwriteRechecksDiskSnapshot() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)
        let before = flow.conflictHunks()

        try tmp.file(".ssh/config", "Host a\n  User second\n")
        await flow.overwrite()
        #expect(flow.phase == .conflict)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User second\n")
        #expect(flow.conflictHunks() != before)

        await flow.overwrite()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n")
    }

    @Test func overwriteAndLoadDiskIgnoredOutsideConflict() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.overwrite()
        flow.loadDiskVersion()
        guard case .review = flow.phase else { Issue.record("review bekleniyordu"); return }
        #expect(app.store.hasUnsavedChanges)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n")
    }

    @Test func overwriteRefusesNonUTF8Disk() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)

        let url = tmp.url.appending(path: ".ssh/config")
        let bytes = Data([0x48, 0xFF])
        try bytes.write(to: url)
        await flow.overwrite()
        guard case .failed = flow.phase else { Issue.record("failed bekleniyordu"); return }
        #expect(try Data(contentsOf: url) == bytes)
    }
}
