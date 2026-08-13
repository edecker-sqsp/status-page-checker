import Foundation

/// The health of a single service, or of the aggregate across all enabled services.
///
/// Ordered from best to worst so that aggregation is simply `reports.map(\.health).max()`.
/// `unknown` sits between `maintenance` and `degraded` deliberately: a check that
/// failed to reach or parse a page is not "all clear" (we genuinely don't know),
/// but it also hasn't confirmed an outage, so it must not read as red.
enum Health: Int, Comparable, Codable, Sendable {
    case operational
    case maintenance
    case unknown
    case degraded
    case outage

    static func < (lhs: Health, rhs: Health) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The emoji shown in the menu bar and next to each service row.
    var emoji: String {
        switch self {
        case .operational, .maintenance:
            return "🟢"
        case .unknown, .degraded:
            return "🟡"
        case .outage:
            return "🔴"
        }
    }

    /// Short human label for the status tab.
    var label: String {
        switch self {
        case .operational: return "Operational"
        case .maintenance: return "Maintenance"
        case .unknown: return "Unknown"
        case .degraded: return "Degraded"
        case .outage: return "Outage"
        }
    }

    /// Whether this state is worth surfacing at the top of the status list /
    /// worth notifying about. Operational and maintenance are "fine".
    var isProblem: Bool {
        self == .degraded || self == .outage || self == .unknown
    }
}
