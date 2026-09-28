import Foundation
import Observation

/// User-configurable state: poll interval and the list of monitored services.
/// Persisted to `UserDefaults` as it changes.
@MainActor
@Observable
final class Settings {
    /// Sub-10s polling of someone else's status API is abusive and risks
    /// getting rate-limited, so the interval the user types is clamped here.
    static let minimumIntervalSeconds = 10
    static let defaultIntervalSeconds = 60

    var intervalSeconds: Int {
        didSet {
            if intervalSeconds != oldValue {
                persist()
            }
        }
    }

    var services: [ServiceConfig] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private enum Key {
        static let interval = "intervalSeconds"
        static let services = "services"
        static let didSeedDefaults = "didSeedDefaults"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.integer(forKey: Key.interval)
        self.intervalSeconds = storedInterval > 0
            ? max(storedInterval, Self.minimumIntervalSeconds)
            : Self.defaultIntervalSeconds

        if let data = defaults.data(forKey: Key.services),
           let decoded = try? JSONDecoder().decode([ServiceConfig].self, from: data) {
            self.services = decoded
        } else if defaults.bool(forKey: Key.didSeedDefaults) {
            // Defaults were seeded before but the array is now empty/corrupt
            // (e.g. the user deleted every custom service and never had
            // built-ins) — respect that rather than re-seeding.
            self.services = []
        } else {
            self.services = ServiceConfig.defaults
            defaults.set(true, forKey: Key.didSeedDefaults)
        }
    }

    /// Clamps to the minimum and persists. UI should call this rather than
    /// setting `intervalSeconds` directly so an out-of-range value typed by
    /// the user can't sneak through.
    func setInterval(_ seconds: Int) {
        intervalSeconds = max(seconds, Self.minimumIntervalSeconds)
    }

    func addService(_ config: ServiceConfig) {
        services.append(config)
    }

    func removeService(id: UUID) {
        services.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    /// Moves the service `id` to `index` (clamped to the array's bounds).
    /// Used by drag-and-drop reordering in Settings.
    func moveService(id: UUID, toIndex index: Int) {
        guard let from = services.firstIndex(where: { $0.id == id }) else { return }
        let to = max(0, min(index, services.count - 1))
        guard from != to else { return }
        let moved = services.remove(at: from)
        services.insert(moved, at: to)
    }

    func updateService(id: UUID, _ mutate: (inout ServiceConfig) -> Void) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        mutate(&services[index])
    }

    private func persist() {
        defaults.set(intervalSeconds, forKey: Key.interval)
        if let data = try? JSONEncoder().encode(services) {
            defaults.set(data, forKey: Key.services)
        }
    }
}
