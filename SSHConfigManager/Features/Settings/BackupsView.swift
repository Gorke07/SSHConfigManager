import SSHConfigKit
import SwiftUI

struct BackupsView: View {
    @State private var backups: BackupsModel
    @State private var confirmingRestore: Backup?
    @State private var confirmingKnownHostsRestore: Backup?

    init(model: AppModel) {
        _backups = State(initialValue: BackupsModel(model: model))
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker(String(localized: "settings.backups"), selection: $backups.fileKind) {
                    Text(String(localized: "backups.kind.config")).tag(BackupFileKind.config)
                    Text(String(localized: "backups.kind.knownHosts")).tag(BackupFileKind.knownHosts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
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
            }
        } detail: {
            if let backup = backups.selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "backups.diffCaption")).font(.headline)
                    DiffTextView(hunks: backups.hunks(for: backup))
                    HStack {
                        if backups.fileKind == .config {
                            Text(String(localized: "backups.restore.note")).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(String(localized: "backups.restore")) {
                            if backups.fileKind == .knownHosts {
                                confirmingKnownHostsRestore = backup
                            } else if backups.model.store.hasUnsavedChanges || backups.model.hasPendingFormEdits {
                                confirmingRestore = backup
                            } else {
                                restore(backup)
                            }
                        }
                        .disabled(restoreDisabled)
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
        .onChange(of: backups.model.knownHosts.revision) { backups.refresh() }
        .onChange(of: ObjectIdentifier(backups.model.knownHosts)) {
            confirmingKnownHostsRestore = nil
            if backups.fileKind == .knownHosts { backups.selectedURL = nil }
            backups.refresh()
        }
        .confirmationDialog(
            String(localized: "backups.restore.knownHosts.title"),
            isPresented: Binding(get: { confirmingKnownHostsRestore != nil }, set: { if !$0 { confirmingKnownHostsRestore = nil } }),
            presenting: confirmingKnownHostsRestore
        ) { backup in
            Button(String(localized: "backups.restore.confirm.action"), role: .destructive) { restore(backup) }
        } message: { _ in
            Text(String(localized: "backups.restore.knownHosts.message"))
        }
        .confirmationDialog(
            String(localized: "backups.restore.confirm.title"),
            isPresented: Binding(get: { confirmingRestore != nil }, set: { if !$0 { confirmingRestore = nil } }),
            presenting: confirmingRestore
        ) { backup in
            Button(String(localized: "backups.restore.confirm.action"), role: .destructive) { restore(backup) }
        }
    }

    private var restoreDisabled: Bool {
        switch backups.fileKind {
        case .config:
            backups.model.store.loadState != .loaded
        case .knownHosts:
            backups.model.knownHosts.loadState != .loaded && backups.model.knownHosts.loadState != .missing
        }
    }

    private func restore(_ backup: Backup) {
        do { try backups.restore(backup) } catch { backups.model.errorMessage = Messages.text(for: error) }
    }
}
