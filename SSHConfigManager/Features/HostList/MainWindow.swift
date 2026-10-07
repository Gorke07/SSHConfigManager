import AppKit
import SSHConfigKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var saveFlow: SaveFlowModel?
    @State private var showExternalDiff = false

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
        .onChange(of: model.store.diskText) { model.resetEditor() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    do { model.select(try HostCommands.addHost(to: model.store)) }
                    catch { model.errorMessage = Messages.text(for: error) }
                } label: {
                    Label(String(localized: "toolbar.addHost"), systemImage: "plus")
                }
                .disabled(model.store.loadState != .loaded)
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
                Button {
                    saveFlow = SaveFlowModel(store: model.store)
                } label: {
                    Label(String(localized: "action.save"), systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.store.hasUnsavedChanges || model.store.isSaving)
            }
        }
        .sheet(item: $saveFlow) { flow in
            SaveSheet(flow: flow) { reloaded in
                if reloaded { model.resetEditor() }
                saveFlow = nil
            }
        }
        .sheet(isPresented: $showExternalDiff) {
            ExternalDiffSheet(store: model.store) { showExternalDiff = false }
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
