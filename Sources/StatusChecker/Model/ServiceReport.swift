import Foundation

/// A single affected component/feature within a service (e.g. "Claude Code",
/// "Git Operations"), shown indented under a non-operational service.
struct ComponentReport: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    /// Humanized status label, e.g. "Partial outage", "Degraded performance".
    let statusLabel: String
}

/// The result of checking one configured service.
struct ServiceReport: Identifiable, Equatable, Sendable {
    var id: UUID { serviceID }
    let serviceID: UUID
    let name: String
    let pageURL: URL
    let health: Health
    /// Human-readable description of what's happening, e.g. an incident title,
    /// or the fetch error text when health == .unknown.
    let description: String
    let affectedComponents: [ComponentReport]
    let checkedAt: Date

    static func unknown(for config: ServiceConfig, reason: String, checkedAt: Date) -> ServiceReport {
        ServiceReport(
            serviceID: config.id,
            name: config.name,
            pageURL: config.pageURL,
            health: .unknown,
            description: reason,
            affectedComponents: [],
            checkedAt: checkedAt
        )
    }
}
