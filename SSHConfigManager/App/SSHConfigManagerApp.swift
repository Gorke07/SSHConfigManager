import SwiftUI

@main
struct SSHConfigManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            MainWindow(model: appDelegate.model)
                .frame(minWidth: 760, minHeight: 480)
                .registersMainWindowOpener(appDelegate)
        }
        Settings {
            SettingsView(model: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
        }
        Window(String(localized: "settings.backups"), id: "backups") {
            BackupsView(model: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
        }
        Window(String(localized: "knownHosts.title"), id: "knownHosts") {
            KnownHostsWindow(app: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
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
