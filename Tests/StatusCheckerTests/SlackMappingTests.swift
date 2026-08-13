import Foundation
import Testing
@testable import StatusChecker

struct SlackMappingTests {

    private func config() -> ServiceConfig {
        ServiceConfig(name: "Slack", pageURL: URL(string: "https://slack-status.com/")!, kind: .slack)
    }

    @Test func okWithNoActiveIncidentsIsOperational() {
        let current = SlackProvider.Current(status: "ok", activeIncidents: [])
        let report = SlackProvider.map(current, config: config(), checkedAt: Date())
        #expect(report.health == .operational)
    }

    @Test func activeIncidentTypeIncidentIsDegraded() {
        let incident = SlackProvider.Incident(
            title: "Elevated error rates",
            type: "incident",
            status: "active",
            url: "https://status.slack.com/incidents/abc",
            services: ["Messaging"]
        )
        let current = SlackProvider.Current(status: "active", activeIncidents: [incident])
        let report = SlackProvider.map(current, config: config(), checkedAt: Date())
        #expect(report.health == .degraded)
        #expect(report.description == "Elevated error rates")
        #expect(report.affectedComponents.map(\.name) == ["Messaging"])
    }

    @Test func activeIncidentTypeOutageIsOutage() {
        let incident = SlackProvider.Incident(
            title: "Slack is down",
            type: "outage",
            status: "active",
            url: nil,
            services: nil
        )
        let current = SlackProvider.Current(status: "active", activeIncidents: [incident])
        let report = SlackProvider.map(current, config: config(), checkedAt: Date())
        #expect(report.health == .outage)
    }

    @Test func scheduledMaintenanceNoticeIsMaintenanceNotDegraded() {
        let incident = SlackProvider.Incident(
            title: "Planned maintenance",
            type: "notice",
            status: "scheduled",
            url: nil,
            services: nil
        )
        let current = SlackProvider.Current(status: "active", activeIncidents: [incident])
        let report = SlackProvider.map(current, config: config(), checkedAt: Date())
        #expect(report.health == .maintenance)
    }

    @Test func worstOfMultipleActiveIncidentsWins() {
        let notice = SlackProvider.Incident(title: "Notice", type: "notice", status: "active", url: nil, services: nil)
        let outage = SlackProvider.Incident(title: "Big outage", type: "outage", status: "active", url: nil, services: nil)
        let current = SlackProvider.Current(status: "active", activeIncidents: [notice, outage])
        let report = SlackProvider.map(current, config: config(), checkedAt: Date())
        #expect(report.health == .outage)
        #expect(report.description == "Big outage")
    }

    /// Decodes the exact shape returned by slack-status.com/api/v2.0.0/current,
    /// confirmed live 2026-08-13.
    @Test func decodesRealResponseShape() throws {
        let json = """
        {"status":"ok","date_created":"2026-08-06T15:22:35-07:00","date_updated":"2026-08-06T18:08:09-07:00","active_incidents":[]}
        """.data(using: .utf8)!
        let current = try JSONDecoder().decode(SlackProvider.Current.self, from: json)
        #expect(current.status == "ok")
        #expect(current.activeIncidents.isEmpty)
    }
}
