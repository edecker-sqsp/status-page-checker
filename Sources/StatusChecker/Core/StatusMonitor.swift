import Foundation
import Observation

/// Owns the poll loop: fans out a check across every enabled service on the
/// configured interval, aggregates the results into a single `Health`, and
/// triggers notifications on state changes.
@MainActor
@Observable
final class StatusMonitor {
    private(set) var reports: [ServiceReport] = []
    private(set) var lastChecked: Date?
    private(set) var isChecking = false

    private let settings: Settings
    private let notificationManager: NotificationManager
    private let session: URLSession
    private var loopTask: Task<Void, Never>?
    /// Health as of the previous cycle, per service, used to detect
    /// transitions worth notifying about. A service with no entry here yet
    /// (first cycle after launch, or newly added) never notifies.
    private var previousHealth: [UUID: Health] = [:]

    /// Called after every completed check (including empty-service-list
    /// checks). The menu bar item observes this to refresh its emoji rather
    /// than relying on SwiftUI observation reaching into AppKit.
    var onChange: (() -> Void)?

    /// Worst health across all enabled services; the emoji shown in the menu
    /// bar. An empty (nothing enabled) list reads as operational rather than
    /// unknown — there's nothing to be worried about.
    var aggregateHealth: Health {
        reports.map(\.health).max() ?? .operational
    }

    /// Reports for display: worst health first, then name, so problems are
    /// always at the top.
    var sortedReports: [ServiceReport] {
        reports.sorted { lhs, rhs in
            if lhs.health != rhs.health { return lhs.health > rhs.health }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    init(settings: Settings, notificationManager: NotificationManager = NotificationManager()) {
        self.settings = settings
        self.notificationManager = notificationManager
        self.session = HTTPFetch.makeSession()
    }

    func start() {
        restart()
    }

    /// Cancels any pending wait and restarts the loop with an immediate
    /// check. Call this after the interval or the service list changes so
    /// edits take effect right away instead of after the old interval drains.
    func restart() {
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.check()
                guard !Task.isCancelled else { return }
                let seconds = self.settings.intervalSeconds
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func check() async {
        isChecking = true
        defer { isChecking = false }

        let configs = settings.services.filter(\.enabled)
        guard !configs.isEmpty else {
            reports = []
            lastChecked = Date()
            onChange?()
            return
        }

        let session = self.session
        let results = await withTaskGroup(of: ServiceReport.self) { group in
            for config in configs {
                group.addTask {
                    await Self.fetchReport(for: config, session: session)
                }
            }
            var collected: [ServiceReport] = []
            for await report in group {
                collected.append(report)
            }
            return collected
        }

        for report in results {
            let notifyEnabled = settings.services.first { $0.id == report.serviceID }?.notify ?? false
            await notificationManager.notifyIfNeeded(
                previous: previousHealth[report.serviceID],
                current: report,
                notifyEnabled: notifyEnabled
            )
            previousHealth[report.serviceID] = report.health
        }

        reports = results
        lastChecked = Date()
        onChange?()
    }

    /// Fetches and maps a single service. Never throws: any failure becomes
    /// an `.unknown` report so one bad page can't block the others.
    nonisolated private static func fetchReport(for config: ServiceConfig, session: URLSession) async -> ServiceReport {
        let provider: StatusProvider = config.kind == .slack ? SlackProvider() : StatuspageProvider()
        do {
            return try await provider.fetchReport(for: config, session: session)
        } catch let error as ProviderError {
            return .unknown(for: config, reason: error.description, checkedAt: Date())
        } catch {
            return .unknown(for: config, reason: error.localizedDescription, checkedAt: Date())
        }
    }
}
