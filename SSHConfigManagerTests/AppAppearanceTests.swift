import AppKit
import Testing
@testable import SSH_Config_Manager

@MainActor
@Suite(.serialized)
struct AppAppearanceTests {
    @Test func applySetsTheAppAppearance() {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }

        AppAppearance.dark.apply()
        #expect(NSApp.appearance?.name == .darkAqua)
        AppAppearance.light.apply()
        #expect(NSApp.appearance?.name == .aqua)
        AppAppearance.system.apply()
        #expect(NSApp.appearance == nil)
    }

    @Test func transitionAlwaysAppliesTheAppearance() async {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }

        await AppAppearance.dark.applyWithTransition()
        #expect(NSApp.appearance?.name == .darkAqua)
        await AppAppearance.system.applyWithTransition()
        #expect(NSApp.appearance == nil)
    }

    @Test func changeDuringATransitionAppliesAtOnce() async {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }

        async let first: Void = AppearanceTransition.perform { NSApp.appearance = NSAppearance(named: .darkAqua) }
        // The first transition is suspended (capturing windows or fading); the second one must not start its own.
        await Task.yield()
        var appliedImmediately = false
        if AppearanceTransition.isRunning {
            await AppearanceTransition.perform { appliedImmediately = true }
            #expect(appliedImmediately)
        }
        await first
        #expect(!AppearanceTransition.isRunning)
        #expect(NSApp.appearance?.name == .darkAqua)
    }

    @Test func windowWithoutAServerWindowHasNoID() {
        // Regression: a negative windowNumber used to trap in the CGWindowID conversion.
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(window.windowNumber <= 0)
        #expect(AppearanceTransition.windowID(of: window) == nil)
    }
}
