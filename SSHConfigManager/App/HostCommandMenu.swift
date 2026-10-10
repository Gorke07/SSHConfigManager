import AppKit
import SSHConfigKit
import SwiftUI

/// "Host" menu (spec v1.1 §4). Main-menu key equivalents win over a window's own key handling, so
/// every item except "New Host" is disabled unless a main window is key; that leaves ⌘↩, ⌘T, ⌘D and
/// ⌘⇧C to the Quick Connect panel and the other windows.
struct HostCommandMenu: Commands {
    let model: AppModel
    let openMainWindow: () -> Void

    var body: some Commands {
        CommandMenu(String(localized: "menu.host")) {
            Button(String(localized: "menu.host.new")) {
                openMainWindow()
                model.addHost()
            }
            .keyboardShortcut("n")
            .disabled(model.store.loadState != .loaded)

            Button(String(localized: "menu.host.duplicate")) {
                guard model.mainWindowIsKey, let item = model.selection else { return }
                model.duplicateHost(item)
            }
            .keyboardShortcut("d")
            .disabled(!model.mainWindowIsKey || !isEditableHost)

            Button(String(localized: "menu.host.delete")) {
                guard model.mainWindowIsKey, let item = model.selection else { return }
                model.requestDelete(item)
            }
            .disabled(!model.mainWindowIsKey || !isEditableHost)

            Divider()

            Button(String(localized: "menu.host.connect")) {
                guard model.mainWindowIsKey, let alias = selectedAlias else { return }
                Task { await model.connect(alias: alias) }
            }
            .keyboardShortcut(.return)
            .disabled(!model.mainWindowIsKey || selectedAlias == nil)

            Button(String(localized: "menu.host.test")) {
                guard model.mainWindowIsKey, let alias = selectedAlias else { return }
                Task { await model.test(alias: alias) }
            }
            .keyboardShortcut("t")
            .disabled(!model.mainWindowIsKey || selectedAlias == nil)

            Button(String(localized: "menu.host.favorite")) {
                guard model.mainWindowIsKey, let alias = selectedAlias else { return }
                model.toggleFavorite(alias)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!model.mainWindowIsKey || selectedAlias == nil)

            Button(String(localized: "menu.host.copyCommand")) {
                guard model.mainWindowIsKey, let item = model.selection else { return }
                model.copySSHCommand(item) { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!model.mainWindowIsKey || selectedAlias == nil)
        }
    }

    private var selectedAlias: String? { model.selection.flatMap(model.connectableAlias(for:)) }

    private var isEditableHost: Bool {
        guard case .host? = model.selection else { return false }
        return model.selection.flatMap { SidebarBuilder.hostEntry(for: $0, in: model.store.document) } != nil
    }
}
