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

    @Test func creditsIncludeSparklesBundledLicense() {
        let text = AboutPanel.credits.string
        #expect(text.contains("Sparkle"))
        #expect(text.contains("Copyright (c) 2006-2013 Andy Matuschak."))
        #expect(text.contains("EXTERNAL LICENSES"))
    }

    @Test func userCancelIsRecognised() {
        #expect(AppLog.isUserCancel(CocoaError(.userCancelled)))
        #expect(AppLog.isUserCancel(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        #expect(!AppLog.isUserCancel(CocoaError(.fileReadNoSuchFile)))
        #expect(!AppLog.isUserCancel(NSError(domain: "other", code: NSUserCancelledError)))
    }

    @Test func logDescriptionsNameTheErrorKindWithoutItsPayloadInThePublicPart() {
        let described = AppLog.describe(KeyManagerError.failed("Load key \"/Users/x/.ssh/id\": bad"))
        #expect(described.kind == "KeyManagerError.failed")
        #expect(!described.kind.contains("/Users"))
        #expect(described.detail.contains("/Users/x/.ssh/id"))   // logged as .private only
    }

    @Test func cocoaErrorKindCarriesNoPathOrPayload() {
        let error = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/x/secret"])
        let described = AppLog.describe(error)
        #expect(!described.kind.contains("/Users"))
        #expect(!described.kind.contains("secret"))
    }

    @Test func payloadFreeEnumCaseIsNamed() {
        #expect(AppLog.describe(KeyManagerError.wrongPassphrase).kind == "KeyManagerError.wrongPassphrase")
    }

    @Test func payloadEnumCaseIsNamedWithoutItsPayload() {
        #expect(AppLog.describe(KeyManagerError.failed("secret /Users/x")).kind == "KeyManagerError.failed")
    }
}
