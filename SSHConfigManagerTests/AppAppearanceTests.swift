import AppKit
import Testing
@testable import SSH_Config_Manager

@MainActor
@Suite(.serialized)
struct AppAppearanceTests {
    @Test(arguments: [false, true])
    func applySetsTheAppAppearance(animated: Bool) {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }

        AppAppearance.dark.apply(animated: animated)
        #expect(NSApp.appearance?.name == .darkAqua)
        AppAppearance.light.apply(animated: animated)
        #expect(NSApp.appearance?.name == .aqua)
        AppAppearance.system.apply(animated: animated)
        #expect(NSApp.appearance == nil)
    }
}
