import SSHConfigKit
import SwiftUI

/// Below the connection bar: what ssh will use for this host (ssh -G) and where each value comes from,
/// then the ProxyJump chain. Only hosts of the saved file qualify, because ssh reads the saved file.
struct EffectiveSettingsView: View {
    @Bindable var model: AppModel
    /// The saved alias, or nil when the host is not (yet) in the saved file.
    let alias: String?
    let isUnsaved: Bool

    /// Sources of the settings, tagged with the alias they were resolved for so a host switch
    /// never shows the previous host's sources. Disclosure state lives on the model (session-wide).
    @State private var resolved: (alias: String, config: ResolvedConfig)?

    var body: some View {
        if let alias {
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(String(localized: "effective.title"), isExpanded: $model.effectiveSettingsExpanded) {
                    settings(for: alias)
                }
                ProxyChainView(model: model, alias: alias)
                    .id(alias)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .task(id: "\(alias)\u{0}\(model.effectiveConfig.generation)") {
                resolved = model.resolvedConfig(forSavedAlias: alias).map { (alias, $0) }
                await model.effectiveConfig.load(alias, using: model.commandBuilder)
            }
        } else if isUnsaved {
            Text(String(localized: "effective.unsaved"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func settings(for alias: String) -> some View {
        let cache = model.effectiveConfig
        if let failure = cache.failure(for: alias) {
            Text(String(localized: "effective.failed \(failure)"))
                .foregroundStyle(.secondary)
        } else if let options = cache.options(for: alias) {
            let rows = EffectiveSettingsBuilder.rows(
                alias: alias, options: options, resolved: resolved(for: alias),
                home: model.settings.homeDirectory, showAll: model.effectiveSettingsShowAll)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(String(localized: "effective.showAll"), isOn: $model.effectiveSettingsShowAll)
                    .toggleStyle(.checkbox)
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(verbatim: row.key).font(.body.monospaced())
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                    Text(verbatim: value).textSelection(.enabled)
                                }
                            }
                            Text(label(for: row.source)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func resolved(for alias: String) -> ResolvedConfig {
        guard let resolved, resolved.alias == alias else { return ResolvedConfig() }
        return resolved.config
    }

    private func label(for source: EffectiveSettingSource) -> String {
        switch source {
        case .thisBlock:
            return String(localized: "effective.source.thisBlock")
        case .otherHost(let patterns):
            let joined = patterns.joined(separator: " ")
            return String(localized: "effective.source.otherHost \(joined)")
        case .global:
            return String(localized: "effective.source.global")
        case .include(let file, _):
            return String(localized: "effective.source.include \(file)")
        case .defaultValue:
            return String(localized: "effective.source.default")
        case .uncertain:
            return String(localized: "effective.source.uncertain")
        }
    }
}
