import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let quickConnect = Self("quickConnect", default: .init(.s, modifiers: [.option, .command]))
}

/// A borderless panel that can take keyboard focus.
final class QuickConnectPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Spotlight-like floating panel opened by the global shortcut (spec §6.3). Closes on Esc,
/// after connecting, and when it loses focus.
@MainActor
final class QuickConnectPanelController: NSObject, NSWindowDelegate {
    private let panel: QuickConnectPanel
    private let model: QuickConnectModel

    init(model: QuickConnectModel, openMainWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        panel = QuickConnectPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            panel.standardWindowButton($0)?.isHidden = true
        }
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickConnectView(
            model: model,
            showsFooter: false,
            dismiss: { [weak self] in self?.close() },
            openMainWindow: openMainWindow,
            openSettings: openSettings))
    }

    func toggle() {
        panel.isVisible ? close() : show()
    }

    func show() {
        model.prepareForDisplay()
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
