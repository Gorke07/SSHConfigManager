import AppKit
import SwiftUI

struct QuickConnectView: View {
    @Bindable var model: QuickConnectModel
    let showsFooter: Bool
    let dismiss: () -> Void
    let openMainWindow: () -> Void
    let openSettings: () -> Void
    var openKnownHosts: (() -> Void)? = nil
    var openKeys: (() -> Void)? = nil
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(String(localized: "quick.search.prompt"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { model.move(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.move(by: 1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.command) {
                        model.testSelected()
                    } else if press.modifiers.contains(.option) {
                        model.copySelectedCommand()
                        dismiss()
                    } else if model.connectSelected() {
                        dismiss()
                    }
                    return .handled
                }
                .onKeyPress(keys: ["s"]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    model.toggleFavoriteSelected()
                    return .handled
                }
            Divider()
            if model.entries.isEmpty {
                Text(String(localized: "quick.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sectionedEntries(), id: \.entry.id) { item in
                                if let header = item.header {
                                    Text(header)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.top, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                row(item.entry).id(item.entry.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: model.selectedIndex) {
                        if let id = model.selectedEntry?.id { proxy.scrollTo(id) }
                    }
                }
            }
            Divider()
            if let entry = model.selectedEntry {
                if let preview = model.previewText(for: entry) {
                    Text(verbatim: preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                } else if model.isPreviewLoading(for: entry) {
                    Text(String(localized: "quick.preview.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
            Text(String(localized: "quick.hint.more"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            if showsFooter {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    footerButton(String(localized: "quick.openMainWindow")) { openMainWindow(); dismiss() }
                    if let openKnownHosts {
                        footerButton(String(localized: "quick.knownHosts")) { openKnownHosts(); dismiss() }
                    }
                    if let openKeys {
                        footerButton(String(localized: "quick.keys")) { openKeys(); dismiss() }
                    }
                    footerButton(String(localized: "quick.settings")) { openSettings(); dismiss() }
                    footerButton(String(localized: "quick.quit")) {
                        // Close the menu first so the unsaved-changes alert is not left behind it.
                        dismiss()
                        Task { @MainActor in NSApp.terminate(nil) }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 420)
        .onAppear { searchFocused = true; model.requestPreview() }
        .onChange(of: model.focusToken) { searchFocused = true }
        .onChange(of: model.selectedIndex) { model.requestPreview() }
        .onChange(of: model.query) { model.requestPreview() }
        .onChange(of: model.app.effectiveConfig.generation) { model.requestPreview() }
    }

    /// Section headers only appear for the empty-query layout (entries carry a section).
    private func sectionedEntries() -> [(entry: QuickConnectEntry, header: String?)] {
        var previous: QuickConnectSection?
        return model.entries.map { entry in
            defer { previous = entry.section }
            guard let section = entry.section, section != previous else { return (entry, nil) }
            return (entry, sectionTitle(section))
        }
    }

    private func sectionTitle(_ section: QuickConnectSection) -> String {
        switch section {
        case .favorites: String(localized: "quick.section.favorites")
        case .recents: String(localized: "quick.section.recents")
        case .all: String(localized: "quick.section.all")
        }
    }

    private func row(_ entry: QuickConnectEntry) -> some View {
        let selected = model.selectedEntry == entry
        return HStack(spacing: 8) {
            ConnectionStatusBadge(model: model.app.connectionTests, alias: entry.alias, showsTitle: false)
                .frame(width: 16)
            Text(FuzzyMatcher.highlighted(entry.alias, offsets: entry.aliasOffsets)).fontWeight(.medium)
            if entry.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityHidden(true) }
            if entry.isIncluded { Image(systemName: "lock").foregroundStyle(.secondary).accessibilityHidden(true) }
            Spacer()
            Text(verbatim: entry.group.map { "\($0) · \(entry.subtitle)" } ?? entry.subtitle).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(entry)
            if model.connectSelected() { dismiss() }
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }
}
