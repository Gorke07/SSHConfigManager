import SwiftUI

@main
struct SSHConfigManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel = SSHConfigManagerApp.makeModel()

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            MainWindow(model: model, appDelegate: appDelegate)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear { appDelegate.model = model }
        }
    }

    @MainActor
    private static func makeModel() -> AppModel {
        guard TestEnvironment.isRunningTests else { return AppModel(settings: AppSettings()) }
        // Unit tests are hosted by the app: use a throwaway home so the real ~/.ssh is never read.
        let home = FileManager.default.temporaryDirectory.appending(path: "SSHConfigManagerTestHost-\(UUID().uuidString)")
        let suite = "SSHConfigManagerTestHost-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        UserDefaults().removePersistentDomain(forName: suite)
        return AppModel(settings: AppSettings(defaults: defaults, homeDirectory: home),
                        backupRoot: home.appending(path: "Backups"))
    }
}
