import Foundation
import Observation
import SSHConfigKit

struct QuickConnectEntry: Identifiable, Hashable, Sendable {
    let alias: String
    let subtitle: String
    let isIncluded: Bool
    var id: String { alias }
}

/// Shared by the menu bar window and the floating panel.
@MainActor
@Observable
final class QuickConnectModel {
    let app: AppModel
    var query = "" {
        didSet { if query != oldValue { selectedIndex = 0 } }
    }
    var selectedIndex = 0
    /// Changes every time the UI is shown, so the view can focus the search field again.
    private(set) var focusToken = UUID()

    /// Opens the main window so a failure alert or fallback notice from a launch is visible.
    private let openMainWindow: @MainActor () -> Void

    init(app: AppModel, openMainWindow: @escaping @MainActor () -> Void = {}) {
        self.app = app
        self.openMainWindow = openMainWindow
    }

    /// Hosts of the saved file only: Connect and Test act on what ssh reads, not on unsaved edits.
    var entries: [QuickConnectEntry] {
        let result = app.savedConnectableHosts.map {
            QuickConnectEntry(alias: $0.entry.alias, subtitle: SidebarBuilder.subtitle(for: $0.entry), isIncluded: $0.isIncluded)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        return result.filter { $0.alias.localizedStandardContains(trimmed) || $0.subtitle.localizedStandardContains(trimmed) }
    }

    var selectedEntry: QuickConnectEntry? {
        let list = entries
        guard !list.isEmpty else { return nil }
        return list[min(max(selectedIndex, 0), list.count - 1)]
    }

    func move(by delta: Int) {
        let count = entries.count
        guard count > 0 else { selectedIndex = 0; return }
        let current = min(max(selectedIndex, 0), count - 1)
        selectedIndex = ((current + delta) % count + count) % count
    }

    func select(_ entry: QuickConnectEntry) {
        if let index = entries.firstIndex(of: entry) { selectedIndex = index }
    }

    @discardableResult
    func connectSelected() -> Bool {
        guard let entry = selectedEntry else { return false }
        if case .launched = app.connect(alias: entry.alias) {} else { openMainWindow() }
        return true
    }

    func testSelected() {
        guard let entry = selectedEntry else { return }
        let builder = app.commandBuilder
        Task { await app.connectionTests.test(entry.alias, using: builder) }
    }

    func prepareForDisplay() {
        query = ""
        selectedIndex = 0
        focusToken = UUID()
    }
}
