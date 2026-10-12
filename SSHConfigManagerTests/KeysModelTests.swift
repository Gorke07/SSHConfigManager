import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
@Suite(.timeLimit(.minutes(1)))
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

    @Test func keyOperationsInvalidateTheLint() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        let before = model.lintRevision
        await model.keys.refresh()
        #expect(model.lintRevision > before)
        let afterRefresh = model.lintRevision
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        #expect(model.lintRevision > afterRefresh)
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
        #expect(model.keys.errorMessage == String(localized: "keys.error.fileExists \(tmp.url.appending(path: ".ssh/taken.pub").path)"))
        for bad in ["", "  ", " k", "k ", "../x", "a/b", ".hidden", "x.pub", "x-cert"] {
            model.keys.errorMessage = nil
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
        await model.keys.refresh()
        #expect(model.keys.rows.first { $0.key.name == "deploy" }?.usedBy == [])   // "Used by" reads the saved file
    }

    @Test func assigningWhileTheFormHasPendingEditsIsRefusedBeforeAnythingHappens() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  HostName 10.0.0.1\n")
        let item = SidebarItem.host(alias: "web", occurrence: 0)
        model.select(item)
        let editor = try #require(model.editor(for: item))
        editor.fields["Port"] = "99999"
        #expect(!editor.commit())
        #expect(model.hasPendingFormEdits)
        #expect(await model.keys.generate(type: .ed25519, fileName: "deploy", comment: "c", passphrase: "", assignTo: "web") == false)
        #expect(model.keys.errorMessage == String(localized: "keys.error.pendingFormEdits"))
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: ".ssh/deploy").path))
        #expect(model.hasPendingFormEdits)
        #expect(model.editor(for: item) === editor)
    }

    @Test func assigningToAnUnknownAliasCreatesNoKey() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        #expect(await model.keys.generate(type: .ed25519, fileName: "deploy", comment: "c", passphrase: "", assignTo: "ghost") == false)
        #expect(model.keys.errorMessage == String(localized: "keys.error.hostNotFound \("ghost")"))
        #expect(!FileManager.default.fileExists(atPath: tmp.url.appending(path: ".ssh/deploy").path))
    }

    @Test func duplicateAliasesAreListedOnce() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\nHost web\nHost db\n")
        #expect(model.assignableAliases == ["web", "db"])
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

    private func keyRow(_ model: AppModel) async throws -> KeyRow {
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        return try #require(model.keys.rows.first)
    }

    @Test func uploadFailuresShowInTheKeysWindowAndLeaveTheMainWindowAlone() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        let row = try await keyRow(model)

        launcher.error = .automationDenied
        #expect(await model.keys.upload(row, alias: "web") == .failed(.automationDenied))
        #expect(model.keys.notice == String(localized: "connect.automationDenied.message"))
        #expect(model.keys.errorMessage == nil)
        #expect(!model.automationDenied && model.errorMessage == nil && model.fallbackNotice == nil)

        launcher.error = .failed("x")
        #expect(await model.keys.upload(row, alias: "web") == .failed(.failed("x")))
        #expect(model.keys.errorMessage == String(localized: "connect.failed \("x")"))
        #expect(!model.automationDenied && model.errorMessage == nil && model.fallbackNotice == nil)
        #expect(launcher.requests.isEmpty)
    }

    @Test func uploadOfAnUnsavedAliasShowsTheNotSavedMessage() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: RecordingLauncher())
        let row = try await keyRow(model)
        #expect(await model.keys.upload(row, alias: "other") == .failed(.notSaved))
        #expect(model.keys.errorMessage == String(localized: "connect.notSaved"))
        #expect(model.errorMessage == nil)
    }

    @Test func uploadFallbackNoticeShowsInTheKeysWindow() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher, isTerminalInstalled: { $0 == .terminal })
        model.settings.setTerminal(.ghostty)
        let row = try await keyRow(model)
        #expect(await model.keys.upload(row, alias: "web") == .fellBack(from: .ghostty))
        #expect(model.keys.notice == String(localized: "connect.fellBack \(TerminalChoice.ghostty.displayName)"))
        #expect(model.fallbackNotice == nil && model.errorMessage == nil)
        #expect(launcher.requests.count == 1)

        model.settings.setTerminal(.terminal)
        #expect(await model.keys.upload(row, alias: "web") == .launched(.terminal))
        #expect(model.keys.errorMessage == nil)
        #expect(launcher.requests.count == 2)
    }

    @Test func trashAlsoMovesAPubFileThatDidNotParse() async throws {
        let tmp = try TempDir()
        let actions = RecordingKeyActions()
        let model = makeTestModel(tmp, config: "Host web\n", keyActions: actions)
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        try tmp.file(".ssh/k.pub", "not a public key\n")
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first)
        #expect(row.key.publicURL == nil)
        #expect(await model.keys.trash(row))
        let moved = try #require(actions.recycled.first).map(\.lastPathComponent)
        #expect(moved == ["k", "k.pub"])
    }

    @Test func agentStateIsUnknownForAKeyWithoutPublicFile() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        try FileManager.default.removeItem(at: tmp.url.appending(path: ".ssh/k.pub"))
        await model.keys.refresh()
        #expect(model.keys.rows.first?.inAgent == nil)
    }

    @Test(.timeLimit(.minutes(1))) func createdButNotAssignedClosesWithAWindowNotice() async throws {
        let tmp = try TempDir()
        let keygen = GatedKeygenRunner()
        let actions = RecordingKeyActions()
        actions.managerRunner = keygen
        let model = makeTestModel(tmp, config: "Host web\n  HostName 10.0.0.1\n", keyActions: actions)
        let item = SidebarItem.host(alias: "web", occurrence: 0)
        model.select(item)
        let editor = try #require(model.editor(for: item))
        let keys = model.keys
        let task = Task { await keys.generate(type: .ed25519, fileName: "deploy", comment: "c", passphrase: "", assignTo: "web") }
        await keygen.waitUntilEntered()          // ssh-keygen is running (suspended); the main actor is free
        editor.fields["Port"] = "99999"            // dirty the form while the key is being made
        #expect(!editor.commit())
        keygen.release()
        #expect(await task.value == true)
        let privateKey = tmp.url.appending(path: ".ssh/deploy").path
        let prefix = String(localized: "keys.error.createdNotAssigned \("~/.ssh/deploy")")
        #expect(keys.notice == prefix + String(localized: "keys.error.pendingFormEdits"))
        #expect(FileManager.default.fileExists(atPath: privateKey))
        #expect(keys.suggestedFileName(for: .ed25519) == "id_ed25519")   // a fresh name, so Create again cannot hit "file exists"
        #expect(!model.store.hasUnsavedChanges)
    }

    @Test func fallbackNoticeSurvivesTheSheetAndAppAlertsAreRestored() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher, isTerminalInstalled: { $0 == .terminal })
        model.settings.setTerminal(.ghostty)                     // not installed -> falls back to Terminal
        model.errorMessage = "unrelated main-window error"
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first)
        guard case .fellBack? = await model.keys.upload(row, alias: "web") else { Issue.record("expected fellBack"); return }
        model.keys.errorMessage = nil                             // what the sheet's onDisappear does
        let name = TerminalChoice.ghostty.displayName
        #expect(model.keys.notice == String(localized: "connect.fellBack \(name)"))
        #expect(model.errorMessage == "unrelated main-window error")
        #expect(model.fallbackNotice == nil)
    }

    @Test func automationDeniedBecomesAWindowNoticeWithTheSettingsButton() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        launcher.error = .automationDenied
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        _ = await model.keys.upload(try #require(model.keys.rows.first), alias: "web")
        #expect(model.keys.notice == String(localized: "connect.automationDenied.message"))
        #expect(model.keys.noticeIsAutomationDenied)
        #expect(model.automationDenied == false)
    }

    @Test func fileNamesEndingInPubOrCertAreRejected() {
        #expect(!KeysModel.isValidFileName("x.pub"))
        #expect(!KeysModel.isValidFileName("x-cert"))
        #expect(KeysModel.isValidFileName("x_cert"))
        #expect(KeysModel.isValidFileName("deploy"))
    }

    @Test func uploadOutcomeStaysInTheKeysWindowWhileTheMainWindowKeepsItsAlert() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        let row = try await keyRow(model)
        var release: CheckedContinuation<Void, Never>?
        launcher.gate = { await withCheckedContinuation { release = $0 } }
        launcher.error = .failed("boom")
        let upload = Task { await model.keys.upload(row, alias: "web") }
        while release == nil { await Task.yield() }
        model.errorMessage = "set while the upload runs"
        launcher.gate = nil
        release?.resume()
        _ = await upload.value
        #expect(model.errorMessage == "set while the upload runs")
        #expect(model.keys.errorMessage == String(localized: "connect.failed \("boom")"))
        #expect(!model.automationDenied && model.fallbackNotice == nil)
    }

    @Test func refreshIfStaleRefreshesWhenNeverRefreshedAndWhenOld() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        let keys = model.keys
        _ = try await TestSupportKeygen.make(tmp.url.appending(path: ".ssh/a"))   // nothing has refreshed yet
        await keys.refreshIfStale()                       // lastRefresh is nil: refreshes
        #expect(keys.rows.map(\.key.name) == ["a"])
        _ = try await TestSupportKeygen.make(tmp.url.appending(path: ".ssh/b"))
        await keys.refreshIfStale()                       // within the 5 s window: no scan
        #expect(keys.rows.map(\.key.name) == ["a"])
        keys.staleAfter = .milliseconds(1)                // the last refresh is now older than the window
        try await Task.sleep(for: .milliseconds(30))
        await keys.refreshIfStale()
        #expect(keys.rows.map(\.key.name) == ["a", "b"])
    }

    @Test func aMissingPassphraseAsksForOneInsteadOfShowingAnError() async throws {
        let tmp = try TempDir()
        let actions = RecordingKeyActions()
        actions.managerRunner = AskedRunner()
        let model = makeTestModel(tmp, config: "Host web\n", keyActions: actions)
        _ = try await TestSupportKeygen.make(tmp.url.appending(path: ".ssh/k"))
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first)
        #expect(await model.keys.addToAgent(row, passphrase: nil))
        #expect(model.keys.passphraseRequestedFor == row.id)
        #expect(model.keys.errorMessage == nil)
    }

    @Test func assignIdentityFileSkipsAnEquivalentSpelling() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  IdentityFile ~/.ssh/../.ssh/k\n")
        _ = try await TestSupportKeygen.make(tmp.url.appending(path: ".ssh/k"))
        try model.assignIdentityFile(tmp.url.appending(path: ".ssh/k"), toAlias: "web")
        let entry = try #require(model.store.document.hosts.first { $0.alias == "web" })
        #expect(entry.values(for: "IdentityFile") == ["~/.ssh/../.ssh/k"])
    }
}

/// Real ssh-keygen on a temp file only.
enum TestSupportKeygen {
    static func make(_ url: URL) async throws -> ProcessResult {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try await ProcessRunner().run(URL(filePath: "/usr/bin/ssh-keygen"),
                                             arguments: ["-q", "-t", "ed25519", "-N", "", "-f", url.path],
                                             environment: [:], timeout: .seconds(30))
    }
}

/// Stands in for ssh-keygen: writes the key pair where it was asked to, but only after the test calls `release()`.
private final class GatedKeygenRunner: ProcessRunning, @unchecked Sendable {
    private let entries: AsyncStream<Void>
    private let entered: AsyncStream<Void>.Continuation
    private let gate: AsyncStream<Void>
    private let opener: AsyncStream<Void>.Continuation

    init() {
        (entries, entered) = AsyncStream.makeStream()
        (gate, opener) = AsyncStream.makeStream()
    }

    func waitUntilEntered() async { for await _ in entries { return } }
    func release() { opener.yield() }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        guard executable.lastPathComponent == "ssh-keygen", let flag = arguments.firstIndex(of: "-f") else {
            return ProcessResult(exitCode: 1, stdout: "", stderr: "", timedOut: false)
        }
        entered.yield()
        for await _ in gate { break }
        let path = arguments[flag + 1]
        FileManager.default.createFile(atPath: path, contents: Data("private".utf8), attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: path + ".pub", contents: Data("public".utf8), attributes: [.posixPermissions: 0o644])
        return ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
    }
}

/// Stands in for ssh-add: asks for the passphrase once (as askpass would), then fails.
private struct AskedRunner: ProcessRunning {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        if executable.lastPathComponent == "ssh-add", let state = environment["SSHCM_ASKPASS_STATE"] {
            FileManager.default.createFile(atPath: state, contents: Data())
            return ProcessResult(exitCode: 1, stdout: "", stderr: "Bad passphrase, try again", timedOut: false)
        }
        return ProcessResult(exitCode: 1, stdout: "", stderr: "", timedOut: false)
    }
}
