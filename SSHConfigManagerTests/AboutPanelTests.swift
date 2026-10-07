import AppKit
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct AboutPanelTests {
    @Test func creditsListKeyboardShortcutsWithItsMITLicense() {
        let text = AboutPanel.credits.string
        #expect(text.contains(String(localized: "about.thirdParty")))
        #expect(text.contains("KeyboardShortcuts"))
        #expect(text.contains("MIT License"))
        #expect(text.contains("Copyright (c) Sindre Sorhus"))
    }

    @Test func logDescriptionsNameTheErrorKindWithoutItsPayloadInThePublicPart() {
        let described = AppLog.describe(KeyManagerError.failed("Load key \"/Users/x/.ssh/id\": bad"))
        #expect(described.kind == "KeyManagerError.failed")
        #expect(!described.kind.contains("/Users"))
        #expect(described.detail.contains("/Users/x/.ssh/id"))   // logged as .private only
    }
}
