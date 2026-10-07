import AppKit

/// Quitting (or closing the last window) with unsaved edits asks Save / Cancel / Don't Save.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel = AppDelegate.makeModel()
    /// Set by every scene (registersMainWindowOpener); reopens it when the Dock icon is clicked or after a failed quit-save.
    var openMainWindow: (() -> Void)?
    private(set) lazy var quickConnect = QuickConnectModel(app: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !TestEnvironment.isRunningTests else { return }
        // The Dock icon is shown only while the main window is open (spec §6.2).
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            nonisolated(unsafe) let object = note.object  // delivered on the main queue
            MainActor.assumeIsolated {
                guard Self.isMainWindow(object) else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            nonisolated(unsafe) let object = note.object  // delivered on the main queue
            MainActor.assumeIsolated {
                guard Self.isMainWindow(object) else { return }
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    /// Closing the window keeps the app running (the menu bar item stays).
    private static func isMainWindow(_ object: Any?) -> Bool {
        (object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") ?? false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openMainWindow?() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.store.hasUnsavedChanges || model.hasPendingFormEdits else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "quit.unsaved.title")
        alert.informativeText = String(localized: "quit.unsaved.message")
        alert.addButton(withTitle: String(localized: "action.save"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        alert.addButton(withTitle: String(localized: "action.discardAndQuit"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if model.hasPendingFormEdits {
                // Saving would silently drop the fields that have problems.
                openMainWindow?()
                NSApp.activate()
                model.errorMessage = String(localized: "quit.pendingForm")
                return .terminateCancel
            }
            Task { @MainActor in
                do {
                    try await model.store.save()
                    sender.reply(toApplicationShouldTerminate: true)
                } catch {
                    openMainWindow?()
                    NSApp.activate()
                    model.errorMessage = Messages.text(for: error)
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    static func makeModel() -> AppModel {
        guard TestEnvironment.isRunningTests else { return AppModel(settings: AppSettings()) }
        // Unit tests are hosted by the app: use a throwaway home so the real ~/.ssh is never read.
        let home = FileManager.default.temporaryDirectory.appending(path: "SSHConfigManagerTestHost-\(UUID().uuidString)")
        let suite = "SSHConfigManagerTestHost-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        UserDefaults().removePersistentDomain(forName: suite)
        return AppModel(settings: AppSettings(defaults: defaults, homeDirectory: home),
                        backupRoot: home.appending(path: "Backups"),
                        launcherFactory: { _ in NoOpLauncher() },
                        isTerminalInstalled: { _ in false })
    }
}

/// Used by the test host so UI driven during tests can never open a real terminal.
private struct NoOpLauncher: TerminalLaunching {
    func launch(_ request: LaunchRequest) throws {}
}
