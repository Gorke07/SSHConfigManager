import Observation
import ServiceManagement

@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Reflects the system's real login-item state; a failed change keeps the old state and explains why.
@MainActor
@Observable
final class LoginItemToggle {
    private(set) var isOn: Bool
    private(set) var errorMessage: String?
    @ObservationIgnored private let item: any LoginItemControlling

    init(item: any LoginItemControlling) {
        self.item = item
        isOn = item.isEnabled
    }

    func set(_ on: Bool) {
        do {
            try item.setEnabled(on)
            errorMessage = nil
        } catch {
            let detail = error.localizedDescription
            errorMessage = String(localized: "settings.launchAtLogin.failed \(detail)")
        }
        isOn = item.isEnabled
    }
}
