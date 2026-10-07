import AppKit
import SSHConfigKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var pendingDelete: SidebarItem?

    var body: some View {
        let sections = SidebarBuilder.sections(
            document: model.store.document, included: model.store.includedHosts, search: model.searchText)
        List(selection: Binding(get: { model.selection }, set: { new in
            guard let new, new != model.selection else { return }
            model.requestSelect(new)
        })) {
            section(String(localized: "sidebar.section.hosts"), rows: sections.hosts, icon: "server.rack", editable: true)
            section(String(localized: "sidebar.section.patterns"), rows: sections.patterns, icon: "asterisk", editable: true)
            section(String(localized: "sidebar.section.included"), rows: sections.included, icon: "lock", editable: false)
            section(String(localized: "sidebar.section.match"), rows: sections.matches, icon: "lock", editable: false)
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button(String(localized: "action.delete"), role: .destructive) {
                guard let item = pendingDelete else { return }
                do {
                    try HostCommands.delete(item, in: model.store)
                    if model.selection == item { model.select(nil) }
                } catch {
                    model.errorMessage = Messages.text(for: error)
                }
                pendingDelete = nil
            }
        } message: {
            Text(String(localized: "delete.confirm.message"))
        }
    }

    private var deleteTitle: String {
        guard case .host(let alias, _)? = pendingDelete else { return "" }
        return String(localized: "delete.confirm.title \(alias)")
    }

    @ViewBuilder
    private func section(_ title: String, rows: [SidebarRow], icon: String, editable: Bool) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label(row.title, systemImage: icon)
                            if let alias = model.connectableAlias(for: row.item) {
                                Spacer()
                                ConnectionStatusBadge(model: model.connectionTests, alias: alias, showsTitle: false)
                            }
                        }
                        if !row.subtitle.isEmpty {
                            Text(verbatim: row.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 24)
                        }
                    }
                    .tag(row.item)
                    .contextMenu {
                        connectItems(for: row.item)
                        if editable {
                            Divider()
                            menu(for: row.item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectItems(for item: SidebarItem) -> some View {
        if let alias = model.connectableAlias(for: item) {
            Button(String(localized: "action.connect")) { model.connect(alias: alias) }
            Button(String(localized: "action.test")) {
                Task { await model.connectionTests.test(alias, using: model.commandBuilder) }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: SidebarItem) -> some View {
        Button(String(localized: "action.duplicate")) {
            do {
                if let copy = try HostCommands.duplicate(item, in: model.store) { model.requestSelect(copy) }
            } catch {
                model.errorMessage = Messages.text(for: error)
            }
        }
        if let command = HostCommands.sshCommand(for: item, document: model.store.document, builder: model.commandBuilder) {
            Button(String(localized: "action.copySSHCommand")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        }
        Divider()
        Button(String(localized: "action.delete"), role: .destructive) { pendingDelete = item }
    }
}
