import SwiftUI

@main
struct SSHConfigManagerApp: App {
    @State private var model: AppModel = SSHConfigManagerApp.makeModel()

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            ContentUnavailableView(
                String(localized: "detail.empty.title"),
                systemImage: "server.rack",
                description: Text(String(localized: "detail.empty.message")))
                .frame(minWidth: 720, minHeight: 440)
        }
    }

    @MainActor
    private static func makeModel() -> AppModel {
        guard TestEnvironment.isRunningTests else { return AppModel(settings: AppSettings()) }
        // Unit tests are hosted by the app: use a throwaway home so the real ~/.ssh is never read.
        let home = FileManager.default.temporaryDirectory.appending(path: "SSHConfigManagerTestHost-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "SSHConfigManagerTestHost")!
        return AppModel(settings: AppSettings(defaults: defaults, homeDirectory: home),
                        backupRoot: home.appending(path: "Backups"))
    }
}
