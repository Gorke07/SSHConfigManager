import AppKit

/// Whether macOS started the app as a login item (spec §3.3: then it starts in the menu bar only).
enum LaunchContext {
    static func isLoginItemLaunch(propertyData: OSType?) -> Bool {
        propertyData == OSType(keyAELaunchedAsLogInItem)
    }

    /// Reads the launch Apple Event; valid only from `applicationDidFinishLaunching` (nil earlier).
    @MainActor
    static func currentLaunchIsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return isLoginItemLaunch(propertyData: event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue)
    }
}
