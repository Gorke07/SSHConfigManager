import SwiftUI

@main
struct SSHConfigManagerApp: App {
    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            ContentUnavailableView(
                String(localized: "detail.empty.title"),
                systemImage: "server.rack",
                description: Text(String(localized: "detail.empty.message")))
                .frame(minWidth: 720, minHeight: 440)
        }
    }
}
