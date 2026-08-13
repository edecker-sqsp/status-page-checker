import Foundation

/// A dependency-free logic check invoked via `StatusChecker --self-check`.
///
/// This exists because, in a Command-Line-Tools-only environment (no Xcode),
/// `swift test` builds the swift-testing bundle fine but the underlying test
/// runner never actually executes it — not even a deliberately failing test
/// produces output or a nonzero exit code, which traces back to missing
/// Xcode-provided test-hosting infrastructure (`xcrun --find xctest` has
/// nothing to find). This exercises the same mapping logic that
/// `Tests/StatusCheckerTests` covers via swift-testing, which remains in the
/// package for whenever a full Xcode toolchain is available.
enum SelfCheck {
    static func run() -> Never {
        var total = 0
        var failed = 0

        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            total += 1
            if condition() {
                print("ok   - \(name)")
            } else {
                failed += 1
                print("FAIL - \(name)")
            }
        }

        func config(_ name: String = "Test", _ url: String = "https://status.example.com/", kind: ProviderKind = .statuspage) -> ServiceConfig {
            ServiceConfig(name: name, pageURL: URL(string: url)!, kind: kind)
        }

        // MARK: Statuspage — real fixtures captured live 2026-08-13

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SelfCheck.swift -> Sources/StatusChecker
            .deletingLastPathComponent() // -> Sources
            .deletingLastPathComponent() // -> repo root
            .appendingPathComponent("Tests/StatusCheckerTests/Fixtures")

        func loadSummary(_ name: String) -> StatuspageProvider.Summary? {
            let url = fixturesDir.appendingPathComponent("\(name).json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(StatuspageProvider.Summary.self, from: data)
        }

        if let summary = loadSummary("statuspage_squarespace_operational") {
            let report = StatuspageProvider.map(summary, config: config("Squarespace"), checkedAt: Date())
            check("Squarespace all-operational maps to .operational", report.health == .operational)
            check("Squarespace has no affected components", report.affectedComponents.isEmpty)
        } else {
            check("loaded Squarespace fixture", false)
        }

        if let summary = loadSummary("statuspage_claude_minor") {
            let report = StatuspageProvider.map(summary, config: config("Claude"), checkedAt: Date())
            check("Claude minor indicator maps to .degraded", report.health == .degraded)
            check("Claude report has a description", !report.description.isEmpty)
            let names = Set(report.affectedComponents.map(\.name))
            check("Claude affected components include claude.ai", names.contains("claude.ai"))
            check("Claude affected components include Claude Code", names.contains("Claude Code"))
        } else {
            check("loaded Claude fixture", false)
        }

        if let summary = loadSummary("statuspage_github_degraded_indicator_none") {
            check("GitHub fixture indicator is literally 'none'", summary.status.indicator == "none")
            let report = StatuspageProvider.map(summary, config: config("GitHub"), checkedAt: Date())
            check("GitHub open incident escalates indicator-none to .degraded", report.health == .degraded)
            check("GitHub description is the open incident's name", report.description == "Disruption with GHEC Team Sync")
        } else {
            check("loaded GitHub fixture", false)
        }

        // MARK: Statuspage — synthetic edge cases

        do {
            let summary = StatuspageProvider.Summary(
                page: .init(name: "Test"),
                status: .init(indicator: "critical", description: "Critical Service Outage"),
                components: [],
                incidents: []
            )
            let report = StatuspageProvider.map(summary, config: config(), checkedAt: Date())
            check("critical indicator maps to .outage", report.health == .outage)
        }

        do {
            let summary = StatuspageProvider.Summary(
                page: .init(name: "Test"),
                status: .init(indicator: "none", description: "All Systems Operational"),
                components: [.init(name: "API", status: "major_outage")],
                incidents: []
            )
            let report = StatuspageProvider.map(summary, config: config(), checkedAt: Date())
            check("major_outage component escalates clean indicator to .outage", report.health == .outage)
            check("affected component carries a humanized label", report.affectedComponents.first?.statusLabel == "Major outage")
        }

        do {
            let summary = StatuspageProvider.Summary(
                page: .init(name: "Test"),
                status: .init(indicator: "none", description: "All Systems Operational"),
                components: [],
                incidents: [.init(name: "Old incident", status: "resolved", impact: "major", shortlink: nil)]
            )
            let report = StatuspageProvider.map(summary, config: config(), checkedAt: Date())
            check("resolved incidents are not escalated", report.health == .operational)
        }

        do {
            let garbage = Data("not json".utf8)
            let cfg = config()
            var decodeFailed = false
            do {
                _ = try JSONDecoder().decode(StatuspageProvider.Summary.self, from: garbage)
            } catch {
                decodeFailed = true
            }
            check("garbage JSON fails to decode", decodeFailed)
            let report = ServiceReport.unknown(for: cfg, reason: "test", checkedAt: Date())
            check("unknown report health is .unknown", report.health == .unknown)
        }

        // MARK: Slack

        func slackConfig() -> ServiceConfig { config("Slack", "https://slack-status.com/", kind: .slack) }

        do {
            let current = SlackProvider.Current(status: "ok", activeIncidents: [])
            let report = SlackProvider.map(current, config: slackConfig(), checkedAt: Date())
            check("Slack ok/no-incidents maps to .operational", report.health == .operational)
        }

        do {
            let incident = SlackProvider.Incident(title: "Elevated error rates", type: "incident", status: "active", url: nil, services: ["Messaging"])
            let current = SlackProvider.Current(status: "active", activeIncidents: [incident])
            let report = SlackProvider.map(current, config: slackConfig(), checkedAt: Date())
            check("Slack type=incident maps to .degraded", report.health == .degraded)
            check("Slack description uses incident title", report.description == "Elevated error rates")
            check("Slack components include the affected service", report.affectedComponents.map(\.name) == ["Messaging"])
        }

        do {
            let incident = SlackProvider.Incident(title: "Slack is down", type: "outage", status: "active", url: nil, services: nil)
            let current = SlackProvider.Current(status: "active", activeIncidents: [incident])
            let report = SlackProvider.map(current, config: slackConfig(), checkedAt: Date())
            check("Slack type=outage maps to .outage", report.health == .outage)
        }

        do {
            let notice = SlackProvider.Incident(title: "Notice", type: "notice", status: "active", url: nil, services: nil)
            let outage = SlackProvider.Incident(title: "Big outage", type: "outage", status: "active", url: nil, services: nil)
            let current = SlackProvider.Current(status: "active", activeIncidents: [notice, outage])
            let report = SlackProvider.map(current, config: slackConfig(), checkedAt: Date())
            check("worst of multiple active Slack incidents wins", report.health == .outage && report.description == "Big outage")
        }

        do {
            let json = Data("""
            {"status":"ok","date_created":"2026-08-06T15:22:35-07:00","date_updated":"2026-08-06T18:08:09-07:00","active_incidents":[]}
            """.utf8)
            if let current = try? JSONDecoder().decode(SlackProvider.Current.self, from: json) {
                check("decodes real Slack response shape", current.status == "ok" && current.activeIncidents.isEmpty)
            } else {
                check("decodes real Slack response shape", false)
            }
        }

        // MARK: Health aggregation

        check(
            "operational < maintenance < unknown < degraded < outage",
            Health.operational < .maintenance && Health.maintenance < .unknown
                && Health.unknown < .degraded && Health.degraded < .outage
        )
        check("unknown does not outrank a real outage", [Health.operational, .degraded, .unknown].max() == .degraded)
        check("outage always wins the max", [Health.unknown, .outage].max() == .outage)
        check("maintenance renders green", Health.maintenance.emoji == "🟢")
        check("degraded and unknown both render yellow", Health.degraded.emoji == "🟡" && Health.unknown.emoji == "🟡")
        check("outage renders red", Health.outage.emoji == "🔴")
        check("empty service list reads as operational", ([Health]().max() ?? .operational) == .operational)

        // MARK: Provider detection (pure normalization, no network)

        check(
            "adds https scheme when missing",
            ProviderDetector.normalizeOrigin("status.example.com")?.absoluteString == "https://status.example.com"
        )
        check(
            "strips path and query",
            ProviderDetector.normalizeOrigin("https://status.example.com/history?foo=bar")?.absoluteString == "https://status.example.com"
        )
        check(
            "preserves explicit http scheme",
            ProviderDetector.normalizeOrigin("http://status.example.com")?.scheme == "http"
        )
        check("rejects empty input", ProviderDetector.normalizeOrigin("") == nil)
        check("rejects whitespace-only input", ProviderDetector.normalizeOrigin("   ") == nil)
        check(
            "recognizes known Slack hosts",
            ProviderDetector.knownSlackHosts.contains("slack-status.com")
                && ProviderDetector.knownSlackHosts.contains("status.slack.com")
        )

        print("")
        print("\(total - failed)/\(total) checks passed")
        exit(failed == 0 ? 0 : 1)
    }
}
