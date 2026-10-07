import AppKit

/// Whether macOS started the app as a login item (spec §3.3: then it starts in the menu bar only).
enum LaunchContext {
    /// Set in `applicationWillFinishLaunching` when macOS started the app at login: no main window, no Dock icon.
    @MainActor static var startsInMenuBar = false

    static func isLoginItemLaunch(propertyData: OSType?) -> Bool {
        propertyData == OSType(keyAELaunchedAsLogInItem)
    }

    /// Reads the launch Apple Event; call from `applicationWillFinishLaunching` / `DidFinishLaunching`.
    @MainActor
    static func currentLaunchIsLoginItem() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let data = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        return isLoginItemLaunch(propertyData: data)
    }
}
