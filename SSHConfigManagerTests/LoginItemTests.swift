import AppKit
import Testing
@testable import SSH_Config_Manager

@MainActor
private final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var needsApproval = false
    var failure: Error?
    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
struct LoginItemTests {
    @Test func togglingUpdatesState() {
        let item = FakeLoginItem()
        let toggle = LoginItemToggle(item: item)
        #expect(!toggle.isOn)
        toggle.set(true)
        #expect(toggle.isOn && item.isEnabled)
        #expect(toggle.errorMessage == nil)
    }

    @Test func failureKeepsRealStateAndExplains() {
        struct Boom: Error {}
        let item = FakeLoginItem()
        item.failure = Boom()
        let toggle = LoginItemToggle(item: item)
        toggle.set(true)
        #expect(!toggle.isOn)
        #expect(toggle.errorMessage?.isEmpty == false)
    }

    @Test func approvalStateIsShownAndRefreshed() {
        let item = FakeLoginItem()
        let toggle = LoginItemToggle(item: item)
        #expect(!toggle.needsApproval)
        item.needsApproval = true
        item.isEnabled = false
        toggle.refresh()
        #expect(toggle.needsApproval && !toggle.isOn)
        item.needsApproval = false
        item.isEnabled = true          // the user approved in System Settings
        toggle.refresh()
        #expect(!toggle.needsApproval && toggle.isOn)
    }

    @Test func loginItemLaunchesAreRecognized() {
        #expect(LaunchContext.isLoginItemLaunch(propertyData: OSType(keyAELaunchedAsLogInItem)))
        #expect(!LaunchContext.isLoginItemLaunch(propertyData: nil))
        #expect(!LaunchContext.isLoginItemLaunch(propertyData: OSType(keyAELaunchedAsServiceItem)))
    }
}
