import Foundation

/// Adapter for Slack's own status API, documented at
/// https://docs.slack.dev/reference/slack-status-api
/// (`https://slack-status.com/api/v2.0.0/current`).
struct SlackProvider: StatusProvider {

    struct Current: Decodable {
        let status: String
        let activeIncidents: [Incident]

        enum CodingKeys: String, CodingKey {
            case status
            case activeIncidents = "active_incidents"
        }
    }

    struct Incident: Decodable {
        let title: String
        let type: String
        let status: String
        let url: String?
        let services: [String]?
    }

    static func endpointURL(origin: URL) -> URL {
        origin.appendingPathComponent("api/v2.0.0/current")
    }

    func fetchReport(for config: ServiceConfig, session: URLSession) async throws -> ServiceReport {
        let checkedAt = Date()
        let origin = StatuspageProvider.origin(of: config.pageURL)
        let data = try await HTTPFetch.getJSON(Self.endpointURL(origin: origin), session: session)
        let current: Current
        do {
            current = try JSONDecoder().decode(Current.self, from: data)
        } catch {
            throw ProviderError("Unrecognized response from \(config.name)")
        }
        return Self.map(current, config: config, checkedAt: checkedAt)
    }

    static func map(_ current: Current, config: ServiceConfig, checkedAt: Date) -> ServiceReport {
        let active = current.activeIncidents.filter { $0.status == "active" || $0.status == "scheduled" }

        guard current.status != "ok" || !active.isEmpty else {
            return ServiceReport(
                serviceID: config.id,
                name: config.name,
                pageURL: config.pageURL,
                health: .operational,
                description: "All systems operational",
                affectedComponents: [],
                checkedAt: checkedAt
            )
        }

        // Worst incident wins; ties broken by picking the first (Slack lists
        // incidents most-recent-first).
        let worst = active.max { health(for: $0) < health(for: $1) }

        let resolvedHealth = active.map(health(for:)).max() ?? .unknown
        let description = worst?.title ?? "Slack is reporting an active incident"
        let components = (worst?.services ?? []).map {
            ComponentReport(name: $0, statusLabel: resolvedHealth.label)
        }

        return ServiceReport(
            serviceID: config.id,
            name: config.name,
            pageURL: config.pageURL,
            health: resolvedHealth,
            description: description,
            affectedComponents: components,
            checkedAt: checkedAt
        )
    }

    private static func health(for incident: Incident) -> Health {
        if incident.status == "scheduled" {
            return .maintenance
        }
        switch incident.type {
        case "outage": return .outage
        case "incident": return .degraded
        case "notice": return .maintenance
        default: return .unknown
        }
    }
}
