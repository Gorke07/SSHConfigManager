import AppKit
import Foundation
import Observation
import SSHConfigKit

enum QuickConnectSection: Hashable, Sendable { case favorites, recents, all }

struct QuickConnectEntry: Identifiable, Hashable, Sendable {
    let alias: String
    let subtitle: String
    let isIncluded: Bool
    var group: String? = nil
    var section: QuickConnectSection? = nil
    var aliasOffsets: [Int] = []
    var isFavorite = false
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

    private let copyToPasteboard: @MainActor (String) -> Void
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(app: AppModel, openMainWindow: @escaping @MainActor () -> Void = {},
         copyToPasteboard: @escaping @MainActor (String) -> Void = {
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString($0, forType: .string)
         }) {
        self.app = app
        self.openMainWindow = openMainWindow
        self.copyToPasteboard = copyToPasteboard
    }

    /// Hosts of the saved file only: Connect and Test act on what ssh reads, not on unsaved edits.
    /// Empty query: favorites, recents, then the rest. Otherwise ranked fuzzy matches.
    var entries: [QuickConnectEntry] {
        let saved = app.savedConnectableHosts
        let base: [QuickConnectEntry] = saved.map { host in
            QuickConnectEntry(
                alias: host.entry.alias,
                subtitle: SidebarBuilder.subtitle(for: host.entry),
                isIncluded: host.isIncluded,
                group: host.isIncluded ? nil : app.store.savedDocument.group(ofHostAt: host.entry.headerLine),
                isFavorite: app.memory.isFavorite(host.entry.alias))
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sectioned(base) }
        let fuzzy = FuzzyQuery(trimmed)
        let recents = app.recentAliases
        let scored: [(QuickConnectEntry, Int, Int)] = base.enumerated().compactMap { index, entry in
            let host = saved[index].entry
            let others = [host.value(for: "HostName"), host.value(for: "User"), entry.group].compactMap { $0 }
            guard let match = FuzzyMatcher.match(fuzzy, alias: entry.alias, others: others) else { return nil }
            var hit = entry
            hit.aliasOffsets = match.aliasOffsets
            let bonus = entry.isFavorite ? 2 : (recents.contains { HostMemory.same($0, entry.alias) } ? 1 : 0)
            return (hit, match.score * 10 + bonus, index)
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map(\.0)
    }

    private func sectioned(_ base: [QuickConnectEntry]) -> [QuickConnectEntry] {
        var used = Set<String>()
        var result: [QuickConnectEntry] = []
        func add(_ alias: String, _ section: QuickConnectSection) {
            guard let entry = base.first(where: { HostMemory.same($0.alias, alias) }),
                  used.insert(EffectiveConfigCache.key(entry.alias)).inserted else { return }
            var copy = entry
            copy.section = section
            result.append(copy)
        }
        app.favoriteAliases.forEach { add($0, .favorites) }
        app.recentAliases.forEach { add($0, .recents) }
        base.forEach { add($0.alias, .all) }
        return result
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

    @discardableResult
    func copySelectedCommand() -> Bool {
        guard let entry = selectedEntry else { return false }
        copyToPasteboard(app.commandBuilder.shellCommand(alias: entry.alias))
        return true
    }

    func toggleFavoriteSelected() {
        guard let entry = selectedEntry else { return }
        app.toggleFavorite(entry.alias)
        // Sections reorder on toggle; keep the selection on the same host.
        if let index = entries.firstIndex(where: { HostMemory.same($0.alias, entry.alias) }) { selectedIndex = index }
        requestPreview()
    }

    /// `user@host:port · via hop`, or nil until ssh -G answered.
    func previewText(for entry: QuickConnectEntry) -> String? {
        guard let options = app.effectiveConfig.options(for: entry.alias), let host = options.first("hostname") else { return nil }
        var text = host
        if let user = options.first("user") { text = user + "@" + text }
        if let port = options.first("port"), port != "22" { text += ":" + port }
        if let hop = options.jumpHops.first {
            let name = hop.host
            text += " · " + String(localized: "quick.preview.via \(name)")
        }
        return text
    }

    /// Nothing answered yet: not loaded and not failed.
    func isPreviewLoading(for entry: QuickConnectEntry) -> Bool {
        app.effectiveConfig.options(for: entry.alias) == nil && app.effectiveConfig.failure(for: entry.alias) == nil
    }

    /// Loads the selected host's ssh -G after a short pause; a new selection cancels it.
    func requestPreview() {
        previewTask?.cancel()
        guard let alias = selectedEntry?.alias else { return }
        let builder = app.commandBuilder
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            await self.app.effectiveConfig.load(alias, using: builder)
        }
    }

    func prepareForDisplay() {
        query = ""
        selectedIndex = 0
        focusToken = UUID()
    }
}
