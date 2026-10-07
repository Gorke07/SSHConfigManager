import SSHConfigKit
import SwiftUI

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let item = model.selection {
            content(for: item)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(for item: SidebarItem) -> some View {
        switch item {
        case .host:
            VStack(spacing: 0) {
                ConnectionBar(model: model, alias: model.connectableAlias(for: item), showsSaveHint: model.isUnsavedHost(item))
                Divider()
                HostEditorContainer(model: model)
                    .id(model.editorToken)
            }
        case .included:
            if let host = SidebarBuilder.includedHost(for: item, in: model.store.includedHosts) {
                VStack(spacing: 0) {
                    ConnectionBar(model: model, alias: model.connectableAlias(for: item))
                    Divider()
                    IncludedHostView(host: host, displayPath: model.settings.displayPath(for: host.file))
                }
            } else {
                empty
            }
        case .match:
            if let match = SidebarBuilder.matchEntry(for: item, in: model.store.document) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "match.readOnly"), systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .padding([.top, .horizontal])
                    CodeTextView(lines: match.text.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { ConfigLine(raw: String($0)) })
                }
            } else {
                empty
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView(
            String(localized: "detail.empty.title"),
            systemImage: "server.rack",
            description: Text(String(localized: "detail.empty.message")))
    }
}

/// Owns the editor model for the current selection; rebuilt only when `editorToken` changes.
private struct HostEditorContainer: View {
    @Bindable var model: AppModel
    @State private var editor: HostEditorModel?

    var body: some View {
        Group {
            if let editor {
                HostEditorView(editor: editor, homeDirectory: model.settings.homeDirectory, keys: model.keys) { model.resetEditor() }
            } else {
                ContentUnavailableView(String(localized: "edit.hostNotFound"), systemImage: "questionmark")
            }
        }
        .onAppear {
            if editor == nil, let item = model.selection {
                editor = model.editor(for: item)
            }
        }
    }
}

private struct IncludedHostView: View {
    let host: IncludedHost
    let displayPath: String

    var body: some View {
        Form {
            Section {
                Label(String(localized: "included.readOnly \(displayPath)"), systemImage: "lock")
                    .foregroundStyle(.secondary)
                LabeledContent(String(localized: "editor.alias")) { Text(verbatim: host.entry.patterns.joined(separator: " ")) }
                ForEach(Array(host.entry.directives.enumerated()), id: \.offset) { _, directive in
                    LabeledContent(directive.key) { Text(verbatim: directive.value).textSelection(.enabled) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
