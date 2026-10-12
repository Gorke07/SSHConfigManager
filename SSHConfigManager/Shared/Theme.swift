import AppKit
import SwiftUI

/// The app's appearance choice (Settings → General). Applied to `NSApp` so every window, sheet,
/// menu and the menu bar panel follow it; `.system` hands control back to macOS.
enum AppAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    var localizedName: String {
        switch self {
        case .system: String(localized: "settings.appearance.system")
        case .light: String(localized: "settings.appearance.light")
        case .dark: String(localized: "settings.appearance.dark")
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }

    /// Cross-fades every visible window to this appearance (`AppearanceTransition`); applies at once with Reduce Motion.
    @MainActor
    func applyWithTransition() async {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            apply()
        } else {
            await AppearanceTransition.perform { apply() }
        }
    }
}

extension NSColor {
    /// Window background: the system color in light mode, a soft graphite black in dark mode
    /// (lighter and slightly cooler than the stock dark gray, so grouped rows and tables still separate).
    static let appBackground = NSColor(name: "appBackground") { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 0x21 / 255, green: 0x22 / 255, blue: 0x26 / 255, alpha: 1)
        }
        return .windowBackgroundColor
    }
}

private struct ThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // Light mode keeps the stock look (white tables, gray grouped forms); dark mode lets the graphite
        // window color show through forms, lists and tables.
        content
            .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
            .containerBackground(Color(nsColor: .appBackground), for: .window)
    }
}

extension View {
    /// Applied once at the root of each window.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}
