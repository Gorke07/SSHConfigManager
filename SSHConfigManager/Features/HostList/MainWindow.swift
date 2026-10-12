import AppKit
import SSHConfigKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var saveFlow: SaveFlowModel?
    @State private var showExternalDiff = false
    @State private var confirmSaveWithPending = false

    private var deleteTitle: String {
        guard case .host(let alias, _)? = model.pendingDelete else { return "" }
        return String(localized: "delete.confirm.title \(alias)")
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                BannerStack(model: model, showExternalDiff: $showExternalDiff)
                DetailView(model: model)
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: String(localized: "sidebar.search.prompt"))
        .onChange(of: model.store.diskText) {
            // Keep a form with blocked edits; the stale guard still protects against external changes.
            if !model.hasPendingFormEdits { model.resetEditor() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.addHost()
                } label: {
                    Label(String(localized: "toolbar.addHost"), systemImage: "plus")
                }
                .disabled(model.store.loadState != .loaded)
            }
            // Liquid Glass groups neighbouring items on one background: Add, then the tools, then Save.
            ToolbarSpacer(.fixed, placement: .primaryAction)
            if !model.statusCounts.isEmpty {
                ToolbarItem(placement: .status) {
                    StatusSummaryView(model: model)
                }
            }
            ToolbarItem(placement: .status) {
                if model.store.hasUnsavedChanges {
                    Label(String(localized: "toolbar.unsaved"), systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if model.connectionTests.isTestingAll {
                    Button {
                        model.connectionTests.cancelAll()
                    } label: {
                        Label(String(localized: "toolbar.stopTesting"), systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        model.connectionTests.testAll(model.connectableAliases, using: model.commandBuilder)
                    } label: {
                        Label(String(localized: "toolbar.testAll"), systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(model.connectableAliases.isEmpty)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "knownHosts")
                } label: {
                    Label(String(localized: "toolbar.knownHosts"), systemImage: "checkmark.shield")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "keys") } label: { Label(String(localized: "toolbar.keys"), systemImage: "key") }
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label(String(localized: "toolbar.settings"), systemImage: "gearshape")
                }
                .help(String(localized: "toolbar.settings.help"))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // An unapplied group draft is applied first; only blocked form edits need the warning.
                    model.applyPendingGroupDraft()
                    if model.hasBlockedFormEdits {
                        confirmSaveWithPending = true
                    } else if model.hasPendingGroupDraft {
                        // The draft could not be applied; its error is showing. Do not save without it.
                    } else {
                        saveFlow = model.makeSaveFlow()
                    }
                } label: {
                    Label(String(localized: "action.save"), systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(model.store.hasUnsavedChanges || model.hasPendingGroupDraft) || model.store.isSaving)
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } })
        ) {
            Button(String(localized: "action.delete"), role: .destructive) { model.confirmPendingDelete() }
        } message: {
            Text(String(localized: "delete.confirm.message"))
        }
        .confirmationDialog(
            String(localized: "saveWithPending.title"), isPresented: $confirmSaveWithPending
        ) {
            Button(String(localized: "action.save")) { saveFlow = model.makeSaveFlow() }
        } message: {
            Text(String(localized: "saveWithPending.message"))
        }
        .confirmationDialog(
            String(localized: "discardForm.title"),
            isPresented: Binding(get: { model.hasPendingDiscardConfirmation }, set: { if !$0 { model.cancelPendingSelection() } })
        ) {
            Button(String(localized: "discardForm.discard"), role: .destructive) { model.confirmPendingSelection() }
        } message: {
            Text(String(localized: "discardForm.message"))
        }
        .sheet(item: $saveFlow) { flow in
            SaveSheet(flow: flow) { reloaded in
                if reloaded { model.resetEditor() }
                saveFlow = nil
            }
        }
        .sheet(item: Binding(get: { model.hostKeyRemoval }, set: { if $0 == nil { model.cancelHostKeyRemoval() } })) { removal in
            HostKeyRemovalSheet(model: model, removal: removal)
        }
        .sheet(isPresented: $showExternalDiff) {
            ExternalDiffSheet(store: model.store) { showExternalDiff = false }
        }
        .alert(String(localized: "connect.automationDenied.title"), isPresented: $model.automationDenied) {
            Button(String(localized: "connect.automationDenied.open")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(String(localized: "action.close"), role: .cancel) {}
        } message: {
            Text(String(localized: "connect.automationDenied.message"))
        }
        .alert(
            String(localized: "connect.fellBack.title"),
            isPresented: Binding(get: { model.fallbackNotice != nil }, set: { if !$0 { model.fallbackNotice = nil } })
        ) {
            Button(String(localized: "action.close")) { model.fallbackNotice = nil }
        } message: {
            Text(model.fallbackNotice ?? "")
        }
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "action.close")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Disk (old) → mine (new) for the "file changed elsewhere" banner.
private struct ExternalDiffSheet: View {
    let store: ConfigStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "conflict.title")).font(.headline)
            DiffTextView(hunks: SaveFlowModel.diskVersusMemory(store))
                .frame(minWidth: 640, minHeight: 360)
            HStack {
                Spacer()
                Button(String(localized: "action.close"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
