import AppKit
import SwiftUI

struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        QuickConnectView(
            model: appDelegate.quickConnect,
            showsFooter: true,
            dismiss: { dismiss() },
            openMainWindow: { appDelegate.openMainWindow?() },
            openSettings: { openSettings(); NSApp.activate() })
            .onAppear { appDelegate.quickConnect.prepareForDisplay() }
    }
}
