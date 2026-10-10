import Foundation
import Observation
import SSHConfigKit

struct KeyRow: Identifiable, Equatable {
    let key: SSHKey
    /// Hosts of the saved file whose IdentityFile names this key.
    let usedBy: [String]
    /// nil: the agent could not be asked.
    let inAgent: Bool?
    let displayPath: String

    var id: String { key.id }
}

@MainActor
@Observable
final class KeysModel {
    private(set) var rows: [KeyRow] = []
    private(set) var isRefreshing = false
    private(set) var isWorking = false
    @ObservationIgnored private var operationCount = 0
    var errorMessage: String?
    /// Window-level message (not cleared when a sheet closes): fallback notices, Automation
    /// denial, "created but not assigned".
    var notice: String?
    var noticeIsAutomationDenied = false
    var selection: String?
    /// Set by the onboarding screen: the Keys window opens its New Key form and clears it.
    var pendingNewKey = false
    /// Set when an agent add without a passphrase found the key encrypted: the window opens the passphrase sheet.
    var passphraseRequestedFor: String?
    /// The key menu in the host form refreshes at most this often.
    @ObservationIgnored var staleAfter: Duration = .seconds(5)
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?

    @ObservationIgnored let tools: KeyTools
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var refreshGeneration = 0

    init(tools: KeyTools) {
        self.tools = tools
    }

    var defaultComment: String {
        "\(NSUserName())@\(Self.hostName())"
    }

    /// `gethostname(3)`, like ssh-keygen's own default comment; `ProcessInfo.hostName` can block on reverse DNS.
    private static func hostName() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) == 0 {
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let name = String(decoding: bytes, as: UTF8.self)
            if !name.isEmpty { return name }
        }
        return ProcessInfo.processInfo.hostName
    }

    func suggestedFileName(for type: SSHKeyType) -> String {
        guard let app else { return type.defaultFileName }
        return KeyManager.nextAvailableURL(fileName: type.defaultFileName, in: app.sshDirectory).lastPathComponent
    }

    /// Refreshes unless a refresh is running or finished recently (each one runs ssh-keygen per key).
    func refreshIfStale() async {
        if isRefreshing { return }
        if let lastRefresh, ContinuousClock.now - lastRefresh < staleAfter { return }
        await refresh()
    }

    func refresh() async {
        guard let app else { return }
        // Called after every key operation, successful or not: the lint reads key files.
        app.invalidateLint()
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        defer { if generation == refreshGeneration { isRefreshing = false } }
        let hosts = app.savedHostEntries
        let home = app.settings.homeDirectory
        let keys = await tools.scanner.scan(directories: app.keyDirectories,
                                            extraPrivateKeys: KeyUsage.identityFiles(of: hosts, home: home))
        let agent = await tools.manager.agentFingerprints()
        guard generation == refreshGeneration else { return }
        lastRefresh = .now
        let labels = KeyUsage.hostLabelsByIdentity(in: hosts, home: home)
        rows = keys.map { key in
            KeyRow(
                key: key,
                usedBy: labels[KeyUsage.identity(key.fileURL)] ?? [],
                inAgent: agent.flatMap { loaded in key.publicKey.map { loaded.contains($0.fingerprint) } },
                displayPath: app.settings.displayPath(for: key.fileURL))
        }
        if let selected = selection, !rows.contains(where: { $0.id == selected }) { selection = nil }
    }

    /// Creates `~/.ssh/<fileName>`; optionally adds it to a host as an unsaved edit (saved by the Save flow).
    func generate(type: SSHKeyType, fileName: String, comment: String, passphrase: String, assignTo alias: String?) async -> Bool {
        guard let app else { return false }
        guard Self.isValidFileName(fileName) else {
            errorMessage = String(localized: "keys.error.invalidFileName")
            return false
        }
        let url = app.sshDirectory.appending(path: fileName)
        if let alias {
            do { try app.validateAssignment(toAlias: alias) } catch {
                AppLog.error(.keys, error)
                errorMessage = Messages.text(for: error)
                return false
            }
        }
        var assignmentError: String?
        let ok = await perform {
            try await tools.manager.generate(type: type, at: url, comment: comment, passphrase: passphrase)
            if let alias {
                do { try app.assignIdentityFile(url, toAlias: alias) } catch {
                    AppLog.error(.keys, error)
                    assignmentError = Messages.text(for: error)
                }
            }
        }
        if let assignmentError {
            // The key exists now; the sheet closes and the window shows the message.
            let shownPath = app.settings.displayPath(for: url)
            notice = String(localized: "keys.error.createdNotAssigned \(shownPath)") + assignmentError
            noticeIsAutomationDenied = false
            return true
        }
        return ok
    }

    /// "Upload to Server…": the outcome is reported in this window's own state; the main window's alerts are
    /// never touched. Nil when another launch is already running.
    @discardableResult
    func upload(_ row: KeyRow, alias: String) async -> Connector.Outcome? {
        guard let app, let pub = row.key.publicURL else { return .failed(.failed("no public key")) }
        guard let outcome = await app.uploadKey(publicKey: pub, alias: alias) else { return nil }
        switch outcome {
        case .launched:
            errorMessage = nil
        case .fellBack(let from):
            let name = from.displayName
            notice = String(localized: "connect.fellBack \(name)")
            noticeIsAutomationDenied = false
        case .failed(.automationDenied):
            notice = String(localized: "connect.automationDenied.message")
            noticeIsAutomationDenied = true
        case .failed(.notSaved):
            errorMessage = String(localized: "connect.notSaved")
        case .failed(.invalidCommand):
            errorMessage = String(localized: "connect.invalidCommand")
        case .failed(let error):
            let detail = error.userMessage ?? ""
            errorMessage = String(localized: "connect.failed \(detail)")
        }
        return outcome
    }

    func addToAgent(_ row: KeyRow, passphrase: String?) async -> Bool {
        guard let url = row.key.privateURL else { return false }
        passphraseRequestedFor = nil
        return await perform {
            do {
                try await tools.manager.addToAgent(url, passphrase: passphrase, useKeychain: tools.useKeychain)
            } catch KeyManagerError.passphraseRequired {
                // Not an error to show: the window asks for the passphrase instead.
                passphraseRequestedFor = row.id
            }
        }
    }

    func changePassphrase(_ row: KeyRow, old: String, new: String) async -> Bool {
        guard let url = row.key.privateURL else { return false }
        return await perform { try await tools.manager.changePassphrase(at: url, old: old, new: new) }
    }

    func copyPublicKey(_ row: KeyRow) {
        guard let url = row.key.publicURL else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            tools.copyToPasteboard(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            AppLog.error(.keys, error)
            errorMessage = Messages.text(for: error)
        }
    }

    /// Moves the private key and its `.pub` to the Trash together (spec §8.3).
    func trash(_ row: KeyRow) async -> Bool {
        var urls = [row.key.privateURL, row.key.publicURL].compactMap { $0 }
        // A `.pub` that did not parse is not in `publicURL`, but the dialog promises both files move.
        if let privateURL = row.key.privateURL {
            let sibling = URL(fileURLWithPath: privateURL.path + ".pub")
            if FileManager.default.fileExists(atPath: sibling.path), !urls.contains(where: { $0.path == sibling.path }) {
                urls.append(sibling)
            }
        }
        return await perform { try await tools.recycle(urls) }
    }

    /// Runs an operation, reports errors, then refreshes the list.
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        operationCount += 1
        isWorking = true
        defer {
            operationCount -= 1
            isWorking = operationCount > 0
        }
        do {
            try await operation()
            errorMessage = nil
            await refresh()
            return true
        } catch {
            AppLog.error(.keys, error)
            errorMessage = Messages.text(for: error)
            await refresh()   // the operation may have changed files before failing
            return false
        }
    }

    static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines) && !name.hasPrefix(".") && !name.contains("/")
            && !name.hasSuffix(".pub") && !name.hasSuffix("-cert")
            && !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
