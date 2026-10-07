import AppKit
import SwiftUI

struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        QuickConnectView(
            model: appDelegate.quickConnect,
            showsFooter: true,
            dismiss: { dismiss() },
            openMainWindow: { appDelegate.openMainWindow?() },
            openSettings: { openSettings(); NSApp.activate() },
            openKnownHosts: {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "knownHosts")
                NSApp.activate()
            })
            .onAppear { appDelegate.quickConnect.prepareForDisplay() }
    }
}
