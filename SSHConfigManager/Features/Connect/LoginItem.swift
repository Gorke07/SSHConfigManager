import Observation
import ServiceManagement

@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    /// Registered but waiting for the user's approval in System Settings → Login Items.
    var needsApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Reflects the system's real login-item state; a failed change keeps the old state and explains why.
@MainActor
@Observable
final class LoginItemToggle {
    private(set) var isOn: Bool
    private(set) var needsApproval: Bool
    private(set) var errorMessage: String?
    @ObservationIgnored private let item: any LoginItemControlling

    init(item: any LoginItemControlling) {
        self.item = item
        isOn = item.isEnabled
        needsApproval = item.needsApproval
    }

    func set(_ on: Bool) {
        do {
            try item.setEnabled(on)
            errorMessage = nil
        } catch {
            AppLog.error(.settings, error)
            let detail = error.localizedDescription
            errorMessage = String(localized: "settings.launchAtLogin.failed \(detail)")
        }
        isOn = item.isEnabled
        needsApproval = item.needsApproval
    }

    /// Re-reads the system state (the user may have changed it in System Settings).
    func refresh() {
        isOn = item.isEnabled
        needsApproval = item.needsApproval
    }
}
