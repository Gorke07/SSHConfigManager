import SwiftUI

@main
struct SSHConfigManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            MainWindow(model: appDelegate.model)
                .frame(minWidth: 760, minHeight: 560)
                .registersMainWindowOpener(appDelegate)
                .themedBackground()
        }
        .commands {
            HostCommandMenu(model: appDelegate.model, openMainWindow: { appDelegate.openMainWindow?() })
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "about.menu")) { AboutPanel.show() }
                Button(String(localized: "update.check")) { appDelegate.updater.checkForUpdates() }
                    .disabled(!appDelegate.updater.canCheckForUpdates)
            }
        }
        Settings {
            SettingsView(model: appDelegate.model, updater: appDelegate.updater)
                .registersMainWindowOpener(appDelegate)
                .themedBackground()
        }
        Window(String(localized: "settings.backups"), id: "backups") {
            BackupsView(model: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
                .themedBackground()
        }
        Window(String(localized: "knownHosts.title"), id: "knownHosts") {
            KnownHostsWindow(app: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
                .themedBackground()
        }
        Window(String(localized: "keys.title"), id: "keys") {
            KeysWindow(app: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
                .themedBackground()
        }
        MenuBarExtra(isInserted: .constant(!TestEnvironment.isRunningTests)) {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel(String(localized: "app.title"))
                .registersMainWindowOpener(appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}
