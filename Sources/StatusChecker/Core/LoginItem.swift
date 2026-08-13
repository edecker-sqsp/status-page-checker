import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`. Deliberately does not cache its
/// own boolean — the settings toggle always reads back the real registration
/// status, so a failed `register()` (e.g. the app isn't running from a stable
/// location like /Applications) shows as off instead of lying to the user.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }
}
