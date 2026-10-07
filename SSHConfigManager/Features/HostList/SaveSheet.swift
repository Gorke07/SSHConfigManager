import SSHConfigKit
import SwiftUI

/// Review → save, or resolve a conflict. `finish(true)` means the document was reloaded from disk.
struct SaveSheet: View {
    @Bindable var flow: SaveFlowModel
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch flow.phase {
            case .preparing:
                ProgressView(String(localized: "save.validating"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .review(let preparation):
                Text(String(localized: "save.title")).font(.headline)
                DiffTextView(hunks: preparation.hunks).frame(minWidth: 640, minHeight: 320)
                validation(preparation.validation)
                HStack {
                    Spacer()
                    Button(String(localized: "action.cancel")) { finish(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "action.save")) { Task { await flow.confirm() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!flow.canConfirm)
                }
            case .saving:
                ProgressView(String(localized: "save.saving"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .conflict:
                Text(String(localized: "conflict.title")).font(.headline)
                Text(String(localized: "conflict.message"))
                DiffTextView(hunks: flow.conflictHunks()).frame(minWidth: 640, minHeight: 280)
                HStack {
                    Button(String(localized: "conflict.loadDisk"), role: .destructive) {
                        flow.loadDiskVersion()
                        finish(true)
                    }
                    Spacer()
                    Button(String(localized: "action.cancel")) { finish(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "conflict.overwrite")) { Task { await flow.overwrite() } }
                }
            case .failed(let message):
                Text(String(localized: "save.failed.title")).font(.headline)
                Text(message).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button(String(localized: "save.retry")) { Task { await flow.prepare() } }
                    Button(String(localized: "action.close")) { finish(false) }
                        .keyboardShortcut(.defaultAction)
                }
            case .done:
                Color.clear.frame(width: 1, height: 1)
                    .onAppear { finish(false) }
            }
        }
        .padding()
        .task { if flow.phase == .preparing { await flow.prepare() } }
    }

    @ViewBuilder
    private func validation(_ outcome: ValidationOutcome) -> some View {
        let valid = outcome == .valid
        Label(Messages.text(for: outcome), systemImage: valid ? "checkmark.seal.fill" : "xmark.octagon.fill")
            .foregroundStyle(valid ? .green : .red)
            .font(valid ? .body : .system(.body, design: .monospaced))
            .textSelection(.enabled)
    }
}
