import SSHConfigKit
import SwiftUI

struct BackupsView: View {
    @State private var backups: BackupsModel
    @State private var confirmingRestore: Backup?

    init(model: AppModel) {
        _backups = State(initialValue: BackupsModel(model: model))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $backups.selectedURL) {
                ForEach(backups.backups, id: \.url) { backup in
                    Text(backup.date.formatted(date: .abbreviated, time: .standard)).tag(backup.url)
                }
            }
            .overlay {
                if backups.backups.isEmpty {
                    ContentUnavailableView(String(localized: "backups.empty"), systemImage: "clock.arrow.circlepath")
                }
            }
        } detail: {
            if let backup = backups.selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "backups.diffCaption")).font(.headline)
                    DiffTextView(hunks: backups.hunks(for: backup))
                    HStack {
                        Text(String(localized: "backups.restore.note")).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "backups.restore")) {
                            if backups.model.store.hasUnsavedChanges || backups.model.hasPendingFormEdits {
                                confirmingRestore = backup
                            } else {
                                restore(backup)
                            }
                        }
                        .disabled(backups.model.store.loadState != .loaded)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView(String(localized: "settings.backups"), systemImage: "clock.arrow.circlepath")
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .onAppear { backups.refresh() }
        .onChange(of: ObjectIdentifier(backups.model.store)) { backups.refresh() }
        .onChange(of: backups.model.store.diskText) { backups.refresh() }
        .confirmationDialog(
            String(localized: "backups.restore.confirm.title"),
            isPresented: Binding(get: { confirmingRestore != nil }, set: { if !$0 { confirmingRestore = nil } }),
            presenting: confirmingRestore
        ) { backup in
            Button(String(localized: "backups.restore.confirm.action"), role: .destructive) { restore(backup) }
        }
    }

    private func restore(_ backup: Backup) {
        do { try backups.restore(backup) } catch { backups.model.errorMessage = Messages.text(for: error) }
    }
}
