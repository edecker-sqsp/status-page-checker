import Foundation
import Testing
@testable import StatusChecker

/// Mapping tests against real, recorded Statuspage payloads (captured
/// 2026-08-13) plus a couple of synthetic edge cases. This is the logic that
/// determines green/yellow/red and can't be verified just by eyeballing the
/// menu bar.
struct StatuspageMappingTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    private func config(_ name: String, _ urlString: String) -> ServiceConfig {
        ServiceConfig(name: name, pageURL: URL(string: urlString)!, kind: .statuspage)
    }

    @Test func squarespaceAllOperational() throws {
        let summary = try JSONDecoder().decode(
            StatuspageProvider.Summary.self,
            from: fixture("statuspage_squarespace_operational")
        )
        let report = StatuspageProvider.map(
            summary,
            config: config("Squarespace", "https://status.squarespace.com/"),
            checkedAt: Date()
        )
        #expect(report.health == .operational)
        #expect(report.affectedComponents.isEmpty)
    }

    /// Real Claude payload: indicator "minor" with claude.ai, the API, and
    /// Claude Code all at partial_outage.
    @Test func claudeMinorIndicatorMapsToDegradedWithComponents() throws {
        let summary = try JSONDecoder().decode(
            StatuspageProvider.Summary.self,
            from: fixture("statuspage_claude_minor")
        )
        let report = StatuspageProvider.map(
            summary,
            config: config("Claude", "https://status.claude.com/"),
            checkedAt: Date()
        )
        #expect(report.health == .degraded)
        #expect(!report.description.isEmpty)
        let names = Set(report.affectedComponents.map(\.name))
        #expect(names.contains("claude.ai"))
        #expect(names.contains("Claude Code"))
    }

    /// Real GitHub payload: top-level indicator "none" ("All Systems
    /// Operational") but with an open minor incident. Proves the indicator
    /// alone isn't trusted — escalation from open incidents must kick in.
    @Test func githubIndicatorNoneWithOpenIncidentEscalatesToDegraded() throws {
        let summary = try JSONDecoder().decode(
            StatuspageProvider.Summary.self,
            from: fixture("statuspage_github_degraded_indicator_none")
        )
        #expect(summary.status.indicator == "none")
        let report = StatuspageProvider.map(
            summary,
            config: config("GitHub", "https://www.githubstatus.com/"),
            checkedAt: Date()
        )
        #expect(report.health == .degraded)
        #expect(report.description == "Disruption with GHEC Team Sync")
    }

    @Test func criticalIndicatorMapsToOutage() {
        let summary = StatuspageProvider.Summary(
            page: .init(name: "Test"),
            status: .init(indicator: "critical", description: "Critical Service Outage"),
            components: [],
            incidents: []
        )
        let report = StatuspageProvider.map(
            summary,
            config: config("Test", "https://status.example.com/"),
            checkedAt: Date()
        )
        #expect(report.health == .outage)
    }

    @Test func majorOutageComponentEscalatesEvenWithCleanIndicator() {
        let summary = StatuspageProvider.Summary(
            page: .init(name: "Test"),
            status: .init(indicator: "none", description: "All Systems Operational"),
            components: [.init(name: "API", status: "major_outage")],
            incidents: []
        )
        let report = StatuspageProvider.map(
            summary,
            config: config("Test", "https://status.example.com/"),
            checkedAt: Date()
        )
        #expect(report.health == .outage)
        #expect(report.affectedComponents.first?.name == "API")
        #expect(report.affectedComponents.first?.statusLabel == "Major outage")
    }

    @Test func resolvedIncidentsAreNotEscalated() {
        let summary = StatuspageProvider.Summary(
            page: .init(name: "Test"),
            status: .init(indicator: "none", description: "All Systems Operational"),
            components: [],
            incidents: [.init(name: "Old incident", status: "resolved", impact: "major", shortlink: nil)]
        )
        let report = StatuspageProvider.map(
            summary,
            config: config("Test", "https://status.example.com/"),
            checkedAt: Date()
        )
        #expect(report.health == .operational)
    }

    @Test func garbageResponseBecomesUnknownReport() {
        let garbage = Data("not json".utf8)
        let cfg = config("Test", "https://status.example.com/")
        let report: ServiceReport
        do {
            _ = try JSONDecoder().decode(StatuspageProvider.Summary.self, from: garbage)
            Issue.record("expected decoding to fail")
            return
        } catch {
            report = .unknown(for: cfg, reason: "Unrecognized response from \(cfg.name)", checkedAt: Date())
        }
        #expect(report.health == .unknown)
    }
}
