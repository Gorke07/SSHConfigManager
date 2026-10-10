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
                EffectiveSettingsView(model: model, alias: model.connectableAlias(for: item), isUnsaved: model.isUnsavedHost(item))
                    .id(model.connectableAlias(for: item) ?? "")
                Divider()
                HostEditorContainer(model: model)
                    .id(model.editorToken)
            }
        case .included:
            if let host = SidebarBuilder.includedHost(for: item, in: model.store.includedHosts) {
                VStack(spacing: 0) {
                    ConnectionBar(model: model, alias: model.connectableAlias(for: item))
                    EffectiveSettingsView(model: model, alias: model.connectableAlias(for: item), isUnsaved: false)
                        .id(model.connectableAlias(for: item) ?? "")
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

    private var showsOnboarding: Bool {
        model.store.loadState == .loaded && model.store.document.hosts.allSatisfy(\.isPattern) && model.store.includedHosts.isEmpty
    }

    @ViewBuilder
    private var empty: some View {
        if model.selection == nil && showsOnboarding {
            OnboardingView(model: model)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
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
                VStack(spacing: 0) {
                    if isRootHost(editor.item) {
                        HostGroupRow(model: model, item: editor.item)
                        LintIssuesList(issues: model.lintIssues(for: editor.item))
                        Divider()
                    }
                    HostEditorView(editor: editor, homeDirectory: model.settings.homeDirectory, keys: model.keys) { model.resetEditor() }
                }
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

/// Root-file, non-pattern hosts only (included hosts and patterns have no group field or lint).
private extension HostEditorContainer {
    func isRootHost(_ item: SidebarItem) -> Bool {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: model.store.document) else { return false }
        return !entry.isPattern
    }
}

private struct HostGroupRow: View {
    let model: AppModel
    let item: SidebarItem
    @State private var groupText = ""

    var body: some View {
        HStack {
            TextField(String(localized: "editor.group"), text: $groupText,
                      prompt: Text(String(localized: "editor.group.placeholder")))
                .onSubmit(apply)
            let groups = model.existingGroups
            if !groups.isEmpty {
                Menu(String(localized: "editor.group.suggestions")) {
                    ForEach(groups, id: \.self) { name in
                        Button { groupText = name; apply() } label: { Text(verbatim: name) }
                    }
                }
                .fixedSize()
            }
            Button(String(localized: "editor.group.apply"), action: apply)
                .disabled(groupText.trimmingCharacters(in: .whitespacesAndNewlines) == savedGroup)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { groupText = savedGroup }
    }

    private var savedGroup: String {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: model.store.document) else { return "" }
        return model.store.document.group(ofHostAt: entry.headerLine) ?? ""
    }

    private func apply() {
        model.setGroup(item, to: groupText)
    }
}

private struct LintIssuesList: View {
    let issues: [HostIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Label(Messages.text(for: issue), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
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
