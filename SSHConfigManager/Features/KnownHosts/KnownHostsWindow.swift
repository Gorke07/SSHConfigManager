import SSHConfigKit
import SwiftUI

struct KnownHostsWindow: View {
    @State private var model: KnownHostsModel

    init(app: AppModel) {
        _model = State(initialValue: KnownHostsModel(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = Messages.knownHostsLoadText(for: model.app.knownHosts.loadState) {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary)
            }
            Table(model.rows, selection: $model.selection) {
                TableColumn(String(localized: "knownHosts.column.host")) { row in
                    HStack(spacing: 4) {
                        if row.isUnparsable {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(String(localized: "knownHosts.unparsable.help"))
                                .accessibilityLabel(String(localized: "knownHosts.unparsable.help"))
                        }
                        if row.isHashed { Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
                        Text(verbatim: row.hosts).lineLimit(1).textSelection(.enabled)
                    }
                }
                TableColumn(String(localized: "knownHosts.column.port")) { row in Text(verbatim: row.ports) }
                    .width(min: 50, ideal: 60)
                TableColumn(String(localized: "knownHosts.column.type")) { row in Text(verbatim: row.keyType) }
                TableColumn(String(localized: "knownHosts.column.fingerprint")) { row in
                    Text(verbatim: row.fingerprint).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                }
                .width(min: 200, ideal: 330)
                TableColumn(String(localized: "knownHosts.column.marker")) { row in Text(verbatim: row.marker) }
                    .width(min: 60, ideal: 110)
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(String(localized: "knownHosts.empty"), systemImage: "checkmark.shield")
                }
            }
            .onDeleteCommand { model.requestRemoveSelection() }
        }
        .searchable(text: $model.searchText, prompt: String(localized: "knownHosts.search.prompt"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    model.requestRemoveSelection()
                } label: {
                    Label(String(localized: "knownHosts.delete"), systemImage: "trash")
                }
                .disabled(!model.canRemoveSelection)
            }
        }
        .confirmationDialog(
            String(localized: "knownHosts.delete.confirm.title"),
            isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.cancelRemoval() } }),
            presenting: model.pendingRemoval
        ) { _ in
            Button(String(localized: "knownHosts.delete"), role: .destructive) { model.confirmRemoval() }
        } message: { rows in
            Text(verbatim: KnownHostsModel.summary(of: rows) + "\n\n" + String(localized: "knownHosts.delete.confirm.message"))
        }
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "action.close")) { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .frame(minWidth: 820, minHeight: 420)
    }
}
