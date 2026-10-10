import SSHConfigKit
import SwiftUI

/// Status badge for one alias: spinner while testing, then the last result.
struct ConnectionStatusBadge: View {
    let model: ConnectionTestsModel
    let alias: String
    let showsTitle: Bool
    /// The connection bar prints the detail next to the badge, so its tooltip omits it.
    var showsDetailInHelp = true

    var body: some View {
        if model.running.contains(alias) {
            badge(ConnectionStatusStyle.testing, detail: nil)
        } else if let result = model.results[alias] {
            badge(ConnectionStatusStyle.style(for: result.status), detail: result.detail)
        }
    }

    private func badge(_ style: ConnectionStatusStyle, detail: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: style.symbol).foregroundStyle(style.tint)
            if showsTitle { Text(style.title) }
        }
        .help(showsDetailInHelp ? (detail.map { style.title + "\n" + $0 } ?? style.title) : style.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.title)
    }
}

/// Above the host form: status, Test and Connect (⌘↩). Patterns, Match blocks and hosts that are
/// not in the saved file pass `alias: nil`.
struct ConnectionBar: View {
    let model: AppModel
    let alias: String?
    var showsSaveHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            buttons
            if showsSaveHint {
                Text(String(localized: "connect.saveToConnect"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if alias != nil && model.store.hasUnsavedChanges {
                Text(String(localized: "connect.usesSavedFile"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var buttons: some View {
        HStack {
            if let alias {
                ConnectionStatusBadge(model: model.connectionTests, alias: alias, showsTitle: true, showsDetailInHelp: false)
                if let detail = model.connectionTests.results[alias]?.detail, !detail.isEmpty {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                if model.connectionTests.results[alias]?.status == .hostKeyChanged {
                    Button(String(localized: "action.removeKnownHost")) {
                        Task { await model.requestHostKeyRemoval(alias: alias) }
                    }
                }
            }
            Spacer()
            if let alias {
                let isFavorite = model.memory.isFavorite(alias)
                let title = isFavorite ? String(localized: "favorite.remove") : String(localized: "favorite.add")
                Button { model.toggleFavorite(alias) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star").foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(title)
                .accessibilityLabel(title)
            }
            Button(String(localized: "action.test")) {
                guard let alias else { return }
                Task { await model.connectionTests.test(alias, using: model.commandBuilder) }
            }
            .disabled(alias == nil || model.connectionTests.running.contains(alias ?? ""))
            Button(String(localized: "action.connect")) {
                if let alias { model.connect(alias: alias) }
            }
            .buttonStyle(.borderedProminent)
            .help(String(localized: "action.connect.help"))
            .disabled(alias == nil)
        }
    }
}
