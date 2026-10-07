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
    var selection: Set<String> = []

    @ObservationIgnored let tools: KeyTools
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var refreshGeneration = 0

    init(tools: KeyTools) {
        self.tools = tools
    }

    var defaultComment: String {
        "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
    }

    func suggestedFileName(for type: SSHKeyType) -> String {
        guard let app else { return type.defaultFileName }
        return KeyManager.nextAvailableURL(fileName: type.defaultFileName, in: app.sshDirectory).lastPathComponent
    }

    func refresh() async {
        guard let app else { return }
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
        rows = keys.map { key in
            KeyRow(
                key: key,
                usedBy: KeyUsage.hosts(using: key.fileURL, in: hosts, home: home),
                inAgent: agent.map { loaded in key.publicKey.map { loaded.contains($0.fingerprint) } ?? false },
                displayPath: app.settings.displayPath(for: key.fileURL))
        }
        selection = selection.filter { id in rows.contains { $0.id == id } }
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
                errorMessage = Messages.text(for: error)
                return false
            }
        }
        return await perform {
            try await tools.manager.generate(type: type, at: url, comment: comment, passphrase: passphrase)
            if let alias { try app.assignIdentityFile(url, toAlias: alias) }
        }
    }

    func addToAgent(_ row: KeyRow, passphrase: String?) async -> Bool {
        guard let url = row.key.privateURL else { return false }
        return await perform {
            try await tools.manager.addToAgent(url, passphrase: passphrase, useKeychain: tools.useKeychain)
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
            errorMessage = Messages.text(for: error)
        }
    }

    /// Moves the private key and its `.pub` to the Trash together (spec §8.3).
    func trash(_ row: KeyRow) async -> Bool {
        let urls = [row.key.privateURL, row.key.publicURL].compactMap { $0 }
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
            errorMessage = Messages.text(for: error)
            await refresh()   // the operation may have changed files before failing
            return false
        }
    }

    static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines) && !name.hasPrefix(".") && !name.contains("/")
            && !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
