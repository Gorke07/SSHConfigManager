import SSHConfigKit
import SwiftUI

struct HostEditorView: View {
    @Bindable var editor: HostEditorModel
    let homeDirectory: URL
    let reload: () -> Void
    @State private var importingIdentity = false

    var body: some View {
        Form {
            if editor.isStale {
                Section {
                    Label(String(localized: "editor.stale"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button(String(localized: "editor.stale.reload"), action: reload)
                }
            }
            Section(String(localized: "editor.section.connection")) {
                TextField(String(localized: "editor.alias"), text: $editor.aliasText)
                field("HostName", help: String(localized: "help.HostName"))
                field("User", help: String(localized: "help.User"))
                field("Port", help: String(localized: "help.Port"))
                field("ProxyJump", help: String(localized: "help.ProxyJump"))
                Picker(selection: binding("ForwardAgent")) {
                    Text(String(localized: "editor.forwardAgent.unset")).tag("")
                    Text(verbatim: "yes").tag("yes")
                    Text(verbatim: "no").tag("no")
                } label: {
                    Text(verbatim: "ForwardAgent")
                }
                .help(String(localized: "help.ForwardAgent"))
            }

            Section(String(localized: "editor.identityFiles")) {
                ForEach(Array(editor.identityFiles.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField(String(localized: "editor.identityFiles"), text: identityBinding(index))
                            .labelsHidden()
                        Button(String(localized: "editor.remove"), systemImage: "minus.circle") {
                            if editor.identityFiles.indices.contains(index) { editor.identityFiles.remove(at: index) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button(String(localized: "editor.identityFiles.add")) { editor.identityFiles.append("") }
                    Button(String(localized: "action.choose")) { importingIdentity = true }
                }
            }

            Section(String(localized: "editor.otherOptions")) {
                ForEach(Array(editor.otherOptions.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField(String(localized: "editor.otherOptions.key"), text: optionBinding(index, \.key))
                        TextField(String(localized: "editor.otherOptions.value"), text: optionBinding(index, \.value))
                        Button(String(localized: "editor.remove"), systemImage: "minus.circle") {
                            if editor.otherOptions.indices.contains(index) { editor.otherOptions.remove(at: index) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Button(String(localized: "editor.otherOptions.add")) {
                    editor.otherOptions.append(DraftDirective(key: "", value: ""))
                }
            }

            if !editor.issues.isEmpty || editor.failure != nil {
                Section(String(localized: "editor.issues")) {
                    ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in
                        Label(Messages.text(for: issue), systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isBlocking ? .red : .orange)
                    }
                    if let error = editor.failure {
                        Label(Messages.text(for: error), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: editor.draft) { editor.commit() }
        .fileImporter(isPresented: $importingIdentity, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                let path = url.standardizedFileURL.path
                let home = homeDirectory.standardizedFileURL.path
                editor.identityFiles.append(path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
            }
        }
    }

    private func field(_ key: String, help: String) -> some View {
        TextField(key, text: binding(key))
            .help(help)
    }

    /// Bounds-safe: a row can outlive its element for one render after a removal.
    private func identityBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { editor.identityFiles.indices.contains(index) ? editor.identityFiles[index] : "" },
            set: { if editor.identityFiles.indices.contains(index) { editor.identityFiles[index] = $0 } })
    }

    private func optionBinding(_ index: Int, _ keyPath: WritableKeyPath<DraftDirective, String>) -> Binding<String> {
        Binding(
            get: { editor.otherOptions.indices.contains(index) ? editor.otherOptions[index][keyPath: keyPath] : "" },
            set: { if editor.otherOptions.indices.contains(index) { editor.otherOptions[index][keyPath: keyPath] = $0 } })
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { editor.fields[key] ?? "" }, set: { editor.fields[key] = $0 })
    }
}
