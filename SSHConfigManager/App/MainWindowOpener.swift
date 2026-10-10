import AppKit
import SwiftUI

/// Every scene registers SwiftUI's `openWindow` with the AppDelegate, so the main window can be
/// reopened (Dock click, menu bar, failed quit-save) whichever scene the app launched with.
private struct MainWindowOpener: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            appDelegate.windowOpener = {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }
}

extension View {
    func registersMainWindowOpener(_ appDelegate: AppDelegate) -> some View {
        modifier(MainWindowOpener(appDelegate: appDelegate))
    }
}
