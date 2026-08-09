import AppKit
import ServiceManagement

@MainActor
final class LoginItemController {
    enum ChangeResult {
        case success
        case requiresApproval
        case failed(String)
    }

    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) -> ChangeResult {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return SMAppService.mainApp.status == .requiresApproval ? .requiresApproval : .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
