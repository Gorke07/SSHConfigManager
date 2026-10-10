import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private enum ImportTarget { case config, knownHosts }
    @State private var importing = false
    @State private var lastImportTarget: ImportTarget?
    @State private var knownHostsInvalid = false
    @State private var pendingPath: String?
    @State private var invalidMessage: String?
    @State private var loginItem = LoginItemToggle(item: MainAppLoginItem())

    var body: some View {
        Form {
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
                KeyboardShortcuts.Recorder(String(localized: "settings.shortcut"), name: .quickConnect)
                if loginItem.needsApproval {
                    Text(String(localized: "settings.launchAtLogin.needsApproval")).font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "settings.launchAtLogin.openSettings")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                if let message = loginItem.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }

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
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
        .frame(width: 520)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.data]
        ) { result in
            let url: URL
            switch result {
            case .success(let picked): url = picked
            case .failure(let error):
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
            Button(String(localized: "settings.switch.discard"), role: .destructive) {
                _ = model.switchConfig(to: path, discardingUnsavedChanges: true)
            }
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
