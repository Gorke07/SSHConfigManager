import SSHConfigKit
import SwiftUI

/// The three buckets the toolbar summary and the sidebar filter group connection results into.
enum StatusCategory: CaseIterable, Hashable {
    case ok, attention, failed

    static func of(_ status: ConnectionStatus) -> StatusCategory {
        switch status {
        case .reachable: .ok
        case .authenticationRequired, .unknownHostKey: .attention
        case .hostKeyChanged, .timeout, .dnsFailure, .connectionRefused, .other: .failed
        }
    }

    var localizedName: String {
        switch self {
        case .ok: String(localized: "status.category.ok")
        case .attention: String(localized: "status.category.attention")
        case .failed: String(localized: "status.category.failed")
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .attention: .orange
        case .failed: .red
        }
    }

    func summary(count: String) -> String {
        switch self {
        case .ok: String(localized: "status.summary.ok \(count)")
        case .attention: String(localized: "status.summary.attention \(count)")
        case .failed: String(localized: "status.summary.failed \(count)")
        }
    }
}

/// Toolbar status item: counts per category of the last connection tests; a tap filters the sidebar.
struct StatusSummaryView: View {
    @Bindable var model: AppModel

    var body: some View {
        let counts = model.statusCounts
        // Nothing to show before a test ran: no empty stack in the toolbar.
        if counts.values.contains(where: { $0 > 0 }) {
            HStack(spacing: 8) {
                ForEach(StatusCategory.allCases, id: \.self) { category in
                    if let count = counts[category], count > 0 {
                        let text = String(count)
                        let help = category.summary(count: text)
                        Button {
                            model.statusFilter = model.statusFilter == category ? nil : category
                        } label: {
                            Label { Text(verbatim: text) } icon: { Image(systemName: category.symbol).foregroundStyle(category.tint) }
                                .labelStyle(.titleAndIcon)
                                .font(.callout)
                        }
                        .buttonStyle(.borderless)
                        .help(help)
                        .accessibilityLabel(help)
                        .accessibilityAddTraits(model.statusFilter == category ? .isSelected : [])
                    }
                }
            }
        }
    }
}
