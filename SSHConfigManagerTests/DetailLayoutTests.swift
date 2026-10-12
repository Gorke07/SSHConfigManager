import AppKit
import SSHConfigKit
import SwiftUI
import Testing
@testable import SSH_Config_Manager

/// `ssh -G` output with the primary keys and many other options (for "Show all").
private final class LongEffectiveConfig: ProcessRunning, @unchecked Sendable {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        var lines = [
            "hostname 10.0.0.5", "user deploy", "port 22", "identityfile ~/.ssh/id_rsa", "identityfile ~/.ssh/id_ecdsa",
            "identityfile ~/.ssh/id_ed25519", "forwardagent no", "identitiesonly no", "serveraliveinterval 0",
            "stricthostkeychecking ask", "userknownhostsfile ~/.ssh/known_hosts ~/.ssh/known_hosts2",
            "controlmaster false", "proxycommand none",
        ]
        lines += (0..<70).map { "option\($0) value\($0)" }
        return ProcessResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n", stderr: "", timedOut: false)
    }
}

/// The main window lays out inside its own height: a detail column taller than the window made the split view
/// fall back to its ideal height and the window showed a blank slice of it (sidebar and form both gone).
@MainActor
struct DetailLayoutTests {
    private func splitViewHeight(windowHeight: CGFloat, showAll: Bool) async throws -> (split: CGFloat, window: CGFloat) {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  HostName 10.0.0.5\n  User deploy\n", runner: LongEffectiveConfig())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1340, height: windowHeight),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: MainWindow(model: model).frame(minWidth: 760, minHeight: 560).themedBackground())
        window.orderFront(nil)
        defer { window.close() }
        model.select(.host(alias: "web", occurrence: 0))
        await model.effectiveConfig.load("web", using: model.commandBuilder)
        try await Task.sleep(for: .milliseconds(300))
        model.effectiveSettingsShowAll = showAll
        model.effectiveSettingsExpanded = true
        try await Task.sleep(for: .milliseconds(600))
        window.layoutIfNeeded()
        func splitView(in view: NSView) -> NSSplitView? { (view as? NSSplitView) ?? view.subviews.lazy.compactMap(splitView(in:)).first }
        let content = try #require(window.contentView)
        let split = try #require(splitView(in: content))
        return (split.frame.height, window.frame.height)
    }

    @Test(arguments: [(882.0, false), (882.0, true), (560.0, false), (560.0, true)])
    func expandedEffectiveSettingsFitTheWindow(height: CGFloat, showAll: Bool) async throws {
        let measured = try await splitViewHeight(windowHeight: height, showAll: showAll)
        #expect(measured.split <= measured.window)
    }
}
