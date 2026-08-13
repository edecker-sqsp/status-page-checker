import Foundation
import UserNotifications

/// Posts a local notification when a service's health changes, if that
/// service has notifications enabled.
///
/// `UNUserNotificationCenter` requires a properly bundled, signed app to grant
/// authorization; under an ad-hoc signature it may simply refuse. Every path
/// here is best-effort and silently no-ops on failure — a missed notification
/// should never affect the rest of the app.
@MainActor
final class NotificationManager {
    private var didRequestAuthorization = false

    /// Whether this process is running from a real app bundle. Running the
    /// raw executable outside a .app (e.g. `swift run` during development)
    /// has no bundle identifier, and `UNUserNotificationCenter` misbehaves in
    /// that context, so skip it entirely rather than risk a crash.
    private var isRunningInBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Compares `previous` (the service's health as of the prior check cycle)
    /// against `current`'s health and posts a notification on a real change.
    /// `previous == nil` means this is the first cycle after launch (or a
    /// newly added service) and is always suppressed, so startup doesn't fire
    /// a burst for every already-broken service.
    func notifyIfNeeded(previous: Health?, current: ServiceReport, notifyEnabled: Bool) async {
        guard isRunningInBundle, notifyEnabled, let previous, previous != current.health else { return }
        // A flaky network producing .unknown shouldn't itself be treated as a
        // state change worth notifying about, in either direction.
        guard previous != .unknown, current.health != .unknown else { return }

        await ensureAuthorized()

        let content = UNMutableNotificationContent()
        content.sound = .default
        if current.health.isProblem {
            content.title = "\(current.name) is \(current.health.label.lowercased())"
            content.body = current.description
        } else {
            content.title = "\(current.name) recovered"
            content.body = "Back to \(current.health.label.lowercased())"
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func ensureAuthorized() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}
