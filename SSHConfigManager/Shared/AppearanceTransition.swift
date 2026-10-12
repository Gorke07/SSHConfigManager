import AppKit
import ScreenCaptureKit

/// Cross-fades every visible window from its current look to a new appearance.
///
/// Views adopt a new appearance over several passes (AppKit chrome, SwiftUI content, and glass and materials that the
/// window server renders), so changing it in place shows each window switching piece by piece. Instead, each window's
/// real pixels are captured first and shown in an overlay above it; the appearance changes underneath, and once
/// everything has redrawn the overlay fades out in one piece. ScreenCaptureKit's `currentProcess` content lets the app
/// capture its own windows without the screen recording permission.
@MainActor
enum AppearanceTransition {
    /// How long the old look stays on screen while the windows redraw underneath; a few frames.
    static let settleDelay: Duration = .milliseconds(120)
    static let fadeDuration: TimeInterval = 0.3

    /// Set before the first suspension, so a second transition started while windows are being captured cannot
    /// create overlays of its own that nobody removes.
    private(set) static var isRunning = false

    /// Runs `change` behind a cross-fade. A change made while a transition runs applies at once, under its overlays.
    /// Windows that cannot be captured simply change in place.
    static func perform(_ change: () -> Void) async {
        guard !isRunning else {
            change()
            return
        }
        isRunning = true
        defer { isRunning = false }
        let windows = NSApp.windows.filter { $0.isVisible && $0.occlusionState.contains(.visible) }
        let overlays = await covers(for: windows)
        change()
        guard !overlays.isEmpty else { return }
        try? await Task.sleep(for: settleDelay)
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlays.forEach { $0.animator().alphaValue = 0 }
        }
        for overlay in overlays {
            overlay.parent?.removeChildWindow(overlay)
            overlay.orderOut(nil)
        }
    }

    /// One borderless, click-through overlay per window, showing its current pixels.
    private static func covers(for windows: [NSWindow]) async -> [NSWindow] {
        guard !windows.isEmpty else { return [] }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.currentProcess
        } catch {
            AppLog.error(.settings, error)
            return []
        }
        var covers: [NSWindow] = []
        for window in windows {
            guard window.isVisible, let id = windowID(of: window),
                  let captured = content.windows.first(where: { $0.windowID == id }),
                  let image = try? await snapshot(of: captured, scale: window.backingScaleFactor) else { continue }
            let cover = NSWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
            cover.isOpaque = false
            cover.backgroundColor = .clear
            cover.hasShadow = false
            cover.ignoresMouseEvents = true
            cover.isReleasedWhenClosed = false
            cover.isExcludedFromWindowsMenu = true
            cover.animationBehavior = .none
            cover.collectionBehavior = [.transient, .ignoresCycle]
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: window.frame.size))
            imageView.image = NSImage(cgImage: image, size: window.frame.size)
            imageView.imageScaling = .scaleAxesIndependently
            cover.contentView = imageView
            window.addChildWindow(cover, ordered: .above)
            covers.append(cover)
        }
        return covers
    }

    /// The window server's ID for `window`, or nil when it has none (`windowNumber` is negative for windows that
    /// were never on screen; converting that to `CGWindowID` would trap).
    static func windowID(of window: NSWindow) -> CGWindowID? {
        CGWindowID(exactly: window.windowNumber).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func snapshot(of window: SCWindow, scale: CGFloat) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
    }
}
