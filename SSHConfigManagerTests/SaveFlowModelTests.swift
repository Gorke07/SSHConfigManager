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
        let app = makeTestModel(tmp, config: "Host a\n", runner: FixedRunner.invalid("line 2: Bad configuration option: bogus"))
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

    @Test func probesTheGivenAlias() async throws {
        final class Recorder: ProcessRunning, @unchecked Sendable {
            let lock = NSLock()
            private var seen: [[String]] = []
            var arguments: [[String]] { lock.withLock { seen } }
            func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
                lock.withLock { seen.append(arguments) }
                return ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
            }
        }
        let tmp = try TempDir()
        let recorder = Recorder()
        let app = makeTestModel(tmp, config: "Host a\nHost b\n", runner: recorder)
        app.select(.host(alias: "b", occurrence: 0))
        try addPort(app)
        let flow = app.makeSaveFlow()
        #expect(flow.probeAlias == "b")
        await flow.prepare()
        await flow.confirm()
        #expect(recorder.arguments.count == 2)
        #expect(recorder.arguments.allSatisfy { $0.last == "b" })

        // The edited (new) alias is probed, not the saved one.
        let editor = try #require(app.editor(for: .host(alias: "b", occurrence: 0)))
        editor.aliasText = "b-new"
        #expect(editor.commit())
        #expect(app.probeAlias == "b-new")
    }

    @Test func unreadableDiskInConflictShowsAReasonNotADiff() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)
        #expect(flow.conflictUnreadableMessage == nil)

        // Not UTF-8: the conflict view gets a note instead of an "everything added" diff (a fresh flow snapshots it).
        let url = tmp.url.appending(path: ".ssh/config")
        try Data([0x48, 0xFF]).write(to: url)
        let second = SaveFlowModel(store: app.store)
        await second.prepare()
        await second.confirm()
        #expect(second.phase == .conflict)
        #expect(second.conflictDiskText == nil)
        #expect(second.conflictUnreadableMessage == Messages.text(for: ConfigLoadState.notUTF8))
        #expect(second.conflictHunks().isEmpty)
    }

    @Test func unreadableDiskKeepsTheRealError() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)
        let url = tmp.url.appending(path: ".ssh/config")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        await flow.overwrite()
        guard case .failed(let message) = flow.phase else { Issue.record("failed bekleniyordu"); return }
        #expect(!message.isEmpty)
        #expect(!message.hasSuffix(": "))
    }

    @Test func documentChangedWhileReviewingIsReviewedAgainNotSaved() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        #expect(flow.canConfirm)

        // Another window edits the document while the sheet is open.
        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "HostName", value: "unseen.example"))
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        await flow.confirm()

        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n")
        guard case .review(let preparation) = flow.phase else { Issue.record("review bekleniyordu"); return }
        #expect(preparation.hunks.flatMap(\.lines).contains { $0.text.contains("unseen.example") })

        await flow.confirm()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n  HostName unseen.example\n")
    }

    @Test func overwriteNeverClobbersAnEditMadeDuringValidation() async throws {
        let tmp = try TempDir()
        let config = tmp.url.appending(path: ".ssh/config")
        // Validation runs: 1 prepare, 2 confirm (→ conflict), 3 overwrite: an editor saves meanwhile.
        let runner = SideEffectRunner(onCall: 3) { try? Data("Host a\n  User newer\n".utf8).write(to: config) }
        let app = makeTestModel(tmp, config: "Host a\n  User u\n", runner: runner)
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)
        #expect(flow.conflictDiskText == "Host a\n  User vim\n")

        await flow.overwrite()

        #expect(try tmp.read(".ssh/config") == "Host a\n  User newer\n")
        #expect(flow.phase == .conflict)
        #expect(flow.conflictDiskText == "Host a\n  User newer\n")

        await flow.overwrite()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n")
    }

    @Test func overwriteAfterTheDocumentChangedShowsTheNewDiffFirst() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)

        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "HostName", value: "unseen.example"))
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        await flow.overwrite()
        #expect(flow.phase == .conflict)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User vim\n")
        #expect(flow.conflictHunks().flatMap(\.lines).contains { $0.text.contains("unseen.example") })

        await flow.overwrite()
        #expect(flow.phase == .done)
    }
}

/// Answers `ssh -G` as valid; runs `action` during the `onCall`-th run (1-based), e.g. to edit the file mid-validation.
private final class SideEffectRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let onCall: Int
    private let action: @Sendable () -> Void

    init(onCall: Int, action: @escaping @Sendable () -> Void) {
        self.onCall = onCall
        self.action = action
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        let call = lock.withLock { calls += 1; return calls }
        if call == onCall { action() }
        return FixedRunner.valid.result
    }
}
