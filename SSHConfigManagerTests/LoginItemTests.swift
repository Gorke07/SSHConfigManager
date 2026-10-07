import Testing
@testable import SSH_Config_Manager

@MainActor
private final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
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
}
