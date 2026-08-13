import Foundation

/// Adapter for the Atlassian Statuspage `/api/v2/summary.json` shape, used by
/// Squarespace, GitHub, Claude, and a large share of other status pages.
struct StatuspageProvider: StatusProvider {

    // MARK: Wire format (only the fields we use)

    struct Summary: Decodable {
        let page: Page
        let status: OverallStatus
        let components: [Component]
        let incidents: [Incident]
    }

    struct Page: Decodable {
        let name: String
    }

    struct OverallStatus: Decodable {
        let indicator: String
        let description: String
    }

    struct Component: Decodable {
        let name: String
        let status: String
    }

    struct Incident: Decodable {
        let name: String
        let status: String
        let impact: String
        let shortlink: String?
    }

    static func summaryURL(origin: URL) -> URL {
        origin.appendingPathComponent("api/v2/summary.json")
    }

    func fetchReport(for config: ServiceConfig, session: URLSession) async throws -> ServiceReport {
        let checkedAt = Date()
        let origin = Self.origin(of: config.pageURL)
        let data = try await HTTPFetch.getJSON(Self.summaryURL(origin: origin), session: session)
        let summary: Summary
        do {
            summary = try JSONDecoder().decode(Summary.self, from: data)
        } catch {
            throw ProviderError("Unrecognized response from \(config.name)")
        }
        return Self.map(summary, config: config, checkedAt: checkedAt)
    }

    /// Scheme + host, stripped of path/query — the base every Statuspage
    /// endpoint hangs off of.
    static func origin(of url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host
        components.port = url.port
        return components.url ?? url
    }

    static func map(_ summary: Summary, config: ServiceConfig, checkedAt: Date) -> ServiceReport {
        let baseHealth = health(forIndicator: summary.status.indicator)

        let unresolvedIncidents = summary.incidents.filter {
            $0.status != "resolved" && $0.status != "postmortem"
        }
        let escalatedFromIncidents = unresolvedIncidents
            .map { health(forImpact: $0.impact) }
            .max() ?? .operational

        let affectedComponents = summary.components.compactMap { component -> ComponentReport? in
            guard let label = componentStatusLabel(component.status) else { return nil }
            return ComponentReport(name: component.name, statusLabel: label)
        }
        let escalatedFromComponents = summary.components
            .map { health(forComponentStatus: $0.status) }
            .max() ?? .operational

        // The top-level indicator can lag reality (a page can read "All Systems
        // Operational" while an incident affecting real components is still
        // open), so the reported health is never allowed to be *lower* than
        // what components or open incidents indicate.
        let resolvedHealth = [baseHealth, escalatedFromIncidents, escalatedFromComponents].max() ?? baseHealth

        let description: String
        if let incident = unresolvedIncidents.first {
            description = incident.name
        } else {
            description = summary.status.description
        }

        return ServiceReport(
            serviceID: config.id,
            name: config.name,
            pageURL: config.pageURL,
            health: resolvedHealth,
            description: description,
            affectedComponents: affectedComponents,
            checkedAt: checkedAt
        )
    }

    private static func health(forIndicator indicator: String) -> Health {
        switch indicator {
        case "none": return .operational
        case "maintenance": return .maintenance
        case "minor": return .degraded
        case "major", "critical": return .outage
        default: return .unknown
        }
    }

    private static func health(forImpact impact: String) -> Health {
        switch impact {
        case "none": return .operational
        case "maintenance": return .maintenance
        case "minor": return .degraded
        case "major", "critical": return .outage
        default: return .unknown
        }
    }

    private static func health(forComponentStatus status: String) -> Health {
        switch status {
        case "operational": return .operational
        case "under_maintenance": return .maintenance
        case "degraded_performance", "partial_outage": return .degraded
        case "major_outage": return .outage
        default: return .operational
        }
    }

    private static func componentStatusLabel(_ status: String) -> String? {
        switch status {
        case "operational": return nil
        case "under_maintenance": return "Under maintenance"
        case "degraded_performance": return "Degraded performance"
        case "partial_outage": return "Partial outage"
        case "major_outage": return "Major outage"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
