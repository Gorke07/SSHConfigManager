import SSHConfigKit
import SwiftUI

struct KeysWindow: View {
    let app: AppModel
    @State private var sheet: KeySheet?
    @State private var trashing: KeyRow?

    enum KeySheet: Identifiable {
        case new, addToAgent(KeyRow), changePassphrase(KeyRow), upload(KeyRow)
        var id: String {
            switch self {
            case .new: "new"
            case .addToAgent(let row): "agent-" + row.id
            case .changePassphrase(let row): "pass-" + row.id
            case .upload(let row): "upload-" + row.id
            }
        }
    }

    private var keys: KeysModel { app.keys }

    var body: some View {
        @Bindable var keys = app.keys
        Table(keys.rows, selection: $keys.selection) {
            TableColumn(String(localized: "keys.column.name")) { row in
                HStack(spacing: 4) {
                    if !row.key.hasPrivateKey {
                        Image(systemName: "key.slash").foregroundStyle(.secondary)
                            .help(String(localized: "keys.noPrivateKey"))
                            .accessibilityLabel(String(localized: "keys.noPrivateKey"))
                    }
                    Text(verbatim: row.displayPath).lineLimit(1).help(row.displayPath)
                }
            }
            TableColumn(String(localized: "keys.column.type")) { row in
                let bits = row.key.bits.map(String.init) ?? ""
                Text(verbatim: [row.key.typeLabel ?? row.key.publicKey?.type ?? "", bits].filter { !$0.isEmpty }.joined(separator: " "))
            }
            .width(min: 70, ideal: 100)
            TableColumn(String(localized: "keys.column.fingerprint")) { row in
                Text(verbatim: row.key.publicKey?.fingerprint ?? "").font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
            }
            .width(min: 180, ideal: 320)
            TableColumn(String(localized: "keys.column.comment")) { row in Text(verbatim: row.key.publicKey?.comment ?? "") }
            TableColumn(String(localized: "keys.column.passphrase")) { row in passphraseCell(row) }
                .width(min: 60, ideal: 80)
            TableColumn(String(localized: "keys.column.agent")) { row in agentCell(row) }
                .width(min: 60, ideal: 80)
            TableColumn(String(localized: "keys.column.usedBy")) { row in
                Text(verbatim: row.usedBy.joined(separator: ", ")).lineLimit(1).help(row.usedBy.joined(separator: "\n"))
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let row = keys.rows.first(where: { ids.contains($0.id) }) { actions(for: row) }
        }
        .overlay {
            if keys.rows.isEmpty && !keys.isRefreshing {
                ContentUnavailableView(String(localized: "keys.empty"), systemImage: "key")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .new } label: { Label(String(localized: "keys.new"), systemImage: "plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await keys.refresh() } } label: {
                    Label(String(localized: "keys.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(keys.isRefreshing)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let row = selectedRow { actions(for: row) }
                } label: {
                    Label(String(localized: "keys.title"), systemImage: "ellipsis.circle")
                }
                .disabled(selectedRow == nil)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .new: NewKeySheet(keys: keys, assignableAliases: app.assignableAliases) { sheet = nil }
            case .addToAgent(let row): AddToAgentSheet(keys: keys, row: row) { sheet = nil }
            case .changePassphrase(let row): ChangePassphraseSheet(keys: keys, row: row) { sheet = nil }
            case .upload(let row): UploadKeySheet(app: app, row: row) { sheet = nil }
            }
        }
        .confirmationDialog(
            String(localized: "keys.trash.title"),
            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
            presenting: trashing
        ) { row in
            Button(String(localized: "keys.trash"), role: .destructive) { Task { _ = await keys.trash(row) } }
        } message: { row in
            let hosts = row.usedBy.joined(separator: ", ")
            Text(row.usedBy.isEmpty ? String(localized: "keys.trash.message")
                 : String(localized: "keys.trash.message") + "\n\n" + String(localized: "keys.trash.inUse \(hosts)"))
        }
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(get: { sheet == nil && keys.errorMessage != nil }, set: { if !$0 { keys.errorMessage = nil } })
        ) {
            Button(String(localized: "action.close")) { keys.errorMessage = nil }
        } message: {
            Text(verbatim: keys.errorMessage ?? "")
        }
        .task { await keys.refresh() }
        .frame(minWidth: 900, minHeight: 420)
    }

    private var selectedRow: KeyRow? {
        keys.rows.first { keys.selection.contains($0.id) }
    }

    @ViewBuilder
    private func actions(for row: KeyRow) -> some View {
        Button(String(localized: "keys.copyPublic")) { keys.copyPublicKey(row) }
            .disabled(row.key.publicURL == nil)
        Button(String(localized: "keys.addToAgent")) {
            if row.key.encryption == .unencrypted {
                Task { _ = await keys.addToAgent(row, passphrase: nil) }
            } else {
                sheet = .addToAgent(row)
            }
        }
        .disabled(!row.key.hasPrivateKey)
        Button(String(localized: "keys.upload")) { sheet = .upload(row) }
            .disabled(row.key.publicURL == nil)
            .help(row.key.publicURL == nil ? String(localized: "keys.upload.noPublicKey") : "")
        Button(String(localized: "keys.changePassphrase")) { sheet = .changePassphrase(row) }
            .disabled(!row.key.hasPrivateKey)
        Divider()
        Button(String(localized: "keys.trash"), role: .destructive) { trashing = row }
    }

    @ViewBuilder
    private func passphraseCell(_ row: KeyRow) -> some View {
        switch row.key.encryption {
        case .encrypted:
            Text(String(localized: "keys.passphrase.yes"))
        case .unencrypted:
            Label(String(localized: "keys.passphrase.no"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(String(localized: "keys.passphrase.noHelp"))
        case .unknown:
            Text(verbatim: "—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func agentCell(_ row: KeyRow) -> some View {
        switch row.inAgent {
        case .some(true):
            Label(String(localized: "keys.agent.loaded"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(false):
            Text(verbatim: "—").foregroundStyle(.secondary)
        case .none:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .help(String(localized: "keys.agent.unknown"))
                .accessibilityLabel(String(localized: "keys.agent.unknown"))
        }
    }
}
