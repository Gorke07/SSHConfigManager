import AppKit

/// The Dock icon follows the open app windows (spec §6.1) unless the user chose menu bar only in Settings.
@MainActor
enum DockIcon {
    /// An app window opened or became key.
    static func showForWindow(_ settings: AppSettings) {
        guard settings.showsInDock else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// The setting changed: hide the icon at once, or show it when an app window is already open.
    static func settingChanged(_ settings: AppSettings) {
        if !settings.showsInDock {
            NSApp.setActivationPolicy(.accessory)
            // Leaving .regular deactivates the app; keep the window the user is working in (Settings) in front.
            NSApp.activate()
        } else if NSApp.windows.contains(where: { ($0.isVisible || $0.isMiniaturized) && AppDelegate.isAppWindow($0) }) {
            NSApp.setActivationPolicy(.regular)
        }
    }
}
