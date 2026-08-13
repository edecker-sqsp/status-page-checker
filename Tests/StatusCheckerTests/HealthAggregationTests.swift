import Foundation
import Testing
@testable import StatusChecker

/// The aggregation rule (`reports.map(\.health).max()`) that decides the
/// single menu bar emoji across every enabled service.
struct HealthAggregationTests {

    @Test func orderingIsOperationalThenMaintenanceThenUnknownThenDegradedThenOutage() {
        #expect(Health.operational < Health.maintenance)
        #expect(Health.maintenance < Health.unknown)
        #expect(Health.unknown < Health.degraded)
        #expect(Health.degraded < Health.outage)
    }

    @Test func unknownDoesNotOutrankARealOutage() {
        #expect([Health.operational, .degraded, .unknown].max() == .degraded)
        #expect([Health.unknown, .outage].max() == .outage)
    }

    @Test func allOperationalStaysGreen() {
        #expect([Health.operational, .operational, .maintenance].max() == .maintenance)
        #expect(Health.maintenance.emoji == "🟢")
    }

    @Test func anyOutageMakesAggregateRed() {
        #expect([Health.operational, .degraded, .outage].max() == .outage)
        #expect(Health.outage.emoji == "🔴")
    }

    @Test func degradedAndUnknownAreBothYellow() {
        #expect(Health.degraded.emoji == "🟡")
        #expect(Health.unknown.emoji == "🟡")
    }

    @Test func emptyServiceListReadsAsOperational() {
        let reports: [Health] = []
        #expect((reports.max() ?? .operational) == .operational)
    }
}
