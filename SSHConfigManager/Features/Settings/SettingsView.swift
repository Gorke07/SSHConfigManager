import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// The Settings tabs. The selection lives in UserDefaults, so other views can open Settings on a given tab.
enum SettingsTab: String {
    case general, files, backups

    static let storageKey = "settingsTab"

    /// Call before `openSettings()`; an open Settings window switches too (@AppStorage observes the default).
    func select(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let updater: AppUpdater
    @Environment(\.openWindow) private var openWindow
    private enum ImportTarget { case config, knownHosts }
    @State private var importing = false
    @State private var lastImportTarget: ImportTarget?
    @State private var knownHostsInvalid = false
    @State private var pendingPath: String?
    @State private var invalidMessage: String?
    @State private var loginItem = LoginItemToggle(item: MainAppLoginItem())

    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            Tab(String(localized: "settings.tab.general"), systemImage: "gearshape", value: SettingsTab.general) {
                pane { general }
            }
            Tab(String(localized: "settings.tab.files"), systemImage: "doc.text", value: SettingsTab.files) {
                pane { files }
            }
            Tab(String(localized: "settings.tab.backups"), systemImage: "clock.arrow.circlepath", value: SettingsTab.backups) {
                pane { backups }
            }
        }
        .frame(width: 640)
        .onAppear { loginItem.refresh(); updater.refreshSettings() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.data]
        ) { result in
            let url: URL
            switch result {
            case .success(let picked): url = picked
            case .failure(let error):
                if AppLog.isUserCancel(error) { return }
                AppLog.error(.settings, error)
                switch lastImportTarget {
                case .config: invalidMessage = String(localized: "settings.configFile.invalid")
                case .knownHosts: knownHostsInvalid = true
                case nil: break
                }
                return
            }
            guard let target = lastImportTarget else { return }
            let path = model.settings.displayPath(for: url)
            switch target {
            case .config: requestSwitch(path)
            case .knownHosts: switchKnownHosts(path)
            }
        }
        .confirmationDialog(
            String(localized: "settings.switch.title"),
            isPresented: Binding(get: { pendingPath != nil }, set: { if !$0 { pendingPath = nil } }),
            presenting: pendingPath
        ) { path in
            Button(String(localized: "settings.switch.save")) {
                Task {
                    switch await model.saveThenSwitchConfig(to: path) {
                    case .switched: invalidMessage = nil
                    case .invalid: invalidMessage = String(localized: "settings.configFile.invalid")
                    case .failed(let message): invalidMessage = message
                    }
                }
            }
            Button(String(localized: "settings.switch.discard"), role: .destructive) {
                _ = model.switchConfig(to: path, discardingUnsavedChanges: true)
            }
        }
    }

    /// One tab's content: a grouped form exactly as tall as its sections, never scrolling. The Settings
    /// window resizes to each tab like the system's own settings windows.
    private func pane(@ViewBuilder _ content: () -> some View) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var general: some View {
        Section(String(localized: "settings.appearance")) {
            // An HStack, not LabeledContent: the label centres on the taller glass control instead of its baseline.
            HStack {
                Text(String(localized: "settings.appearance"))
                Spacer()
                AppearancePicker(selection: Binding(
                    get: { model.settings.appearance },
                    set: { model.settings.setAppearance($0); $0.apply(animated: true) }
                ))
                .accessibilityLabel(String(localized: "settings.appearance"))
            }
            Toggle(String(localized: "settings.showsInDock"), isOn: Binding(
                get: { model.settings.showsInDock },
                set: { model.settings.setShowsInDock($0); DockIcon.settingChanged(model.settings) }
            ))
            if !model.settings.showsInDock {
                Text(String(localized: "settings.showsInDock.note")).font(.footnote).foregroundStyle(.secondary)
            }
        }

        Section(String(localized: "settings.connection")) {
            Picker(String(localized: "settings.terminal"), selection: Binding(
                get: { model.settings.terminal },
                set: { model.settings.setTerminal($0) }
            )) {
                ForEach(TerminalChoice.allCases, id: \.self) { choice in
                    let name = choice.displayName
                    Text(verbatim: model.isTerminalInstalled(choice) ? name : String(localized: "settings.terminal.notInstalled \(name)"))
                        .tag(choice)
                        .selectionDisabled(!model.isTerminalInstalled(choice))
                }
            }
            Toggle(String(localized: "settings.launchAtLogin"), isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
            if loginItem.needsApproval {
                Text(String(localized: "settings.launchAtLogin.needsApproval")).font(.footnote).foregroundStyle(.secondary)
                Button(String(localized: "settings.launchAtLogin.openSettings")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if let message = loginItem.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            KeyboardShortcuts.Recorder(String(localized: "settings.shortcut"), name: .quickConnect)
        }

        Section(String(localized: "settings.updates")) {
            Toggle(String(localized: "settings.updates.automaticCheck"), isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecksForUpdates($0) }
            ))
            Toggle(String(localized: "settings.updates.automaticDownload"), isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.setAutomaticallyDownloadsUpdates($0) }
            ))
            .disabled(!updater.automaticallyChecksForUpdates)
            let version = AppUpdater.currentVersion
            LabeledContent(String(localized: "settings.updates.version \(version)")) {
                Button(String(localized: "update.check")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        Section(String(localized: "settings.language")) {
            Text(String(localized: "settings.language.note"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(String(localized: "settings.language.open")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder private var files: some View {
        Section(String(localized: "settings.configFile")) {
            LabeledContent(String(localized: "settings.configFile")) {
                Text(verbatim: model.settings.configPath).textSelection(.enabled)
            }
            HStack {
                Button(String(localized: "action.choose")) { lastImportTarget = .config; importing = true }
                Button(String(localized: "settings.configFile.useDefault")) { requestSwitch(AppSettings.defaultConfigPath) }
                    .disabled(model.commandBuilder.usesDefaultConfig)
            }
            if let invalidMessage {
                Text(verbatim: invalidMessage).font(.footnote).foregroundStyle(.red)
            }
            if !model.commandBuilder.usesDefaultConfig {
                Text(String(localized: "settings.configFile.customNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section(String(localized: "settings.knownHostsFile")) {
            LabeledContent(String(localized: "settings.knownHostsFile")) {
                Text(verbatim: model.settings.knownHostsPath).textSelection(.enabled)
            }
            HStack {
                Button(String(localized: "action.choose")) { lastImportTarget = .knownHosts; importing = true }
                Button(String(localized: "settings.knownHostsFile.useDefault")) {
                    switchKnownHosts(AppSettings.defaultKnownHostsPath)
                }
                .disabled(model.settings.knownHostsPath == AppSettings.defaultKnownHostsPath)
            }
            if knownHostsInvalid {
                Text(String(localized: "settings.knownHostsFile.invalid")).font(.footnote).foregroundStyle(.red)
            }
            if model.settings.knownHostsPath != AppSettings.defaultKnownHostsPath {
                Text(String(localized: "settings.knownHostsFile.customNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var backups: some View {
        Section(String(localized: "settings.backups")) {
            let count = String(model.settings.backupCount)
            Stepper(
                value: Binding(get: { model.settings.backupCount }, set: { model.setBackupCount($0) }),
                in: AppSettings.backupCountRange
            ) {
                Text(String(localized: "settings.backups.count \(count)"))
            }
            Button(String(localized: "settings.backups.show")) { openWindow(id: "backups") }
        }
    }

    private func switchKnownHosts(_ path: String) {
        knownHostsInvalid = !model.switchKnownHosts(to: path)
    }

    private func requestSwitch(_ path: String) {
        invalidMessage = nil
        switch model.switchConfig(to: path) {
        case .needsConfirmation: pendingPath = path
        case .invalid: invalidMessage = String(localized: "settings.configFile.invalid")
        case .switched, .unchanged: break
        }
    }
}
