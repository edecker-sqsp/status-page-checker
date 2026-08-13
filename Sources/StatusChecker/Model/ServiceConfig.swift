import Foundation

/// Which adapter should be used to check a service's page.
enum ProviderKind: String, Codable, Sendable {
    case statuspage
    case slack
}

/// A configured service to monitor: one of the four built-ins, or a
/// user-added custom page.
struct ServiceConfig: Identifiable, Codable, Equatable, Sendable, Hashable {
    let id: UUID
    var name: String
    var pageURL: URL
    var kind: ProviderKind
    var enabled: Bool
    var notify: Bool
    /// Built-ins can be disabled but not deleted from the settings UI.
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        pageURL: URL,
        kind: ProviderKind,
        enabled: Bool = true,
        notify: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pageURL = pageURL
        self.kind = kind
        self.enabled = enabled
        self.notify = notify
        self.isBuiltIn = isBuiltIn
    }

    /// The four services requested at launch, seeded on first run.
    static var defaults: [ServiceConfig] {
        [
            ServiceConfig(
                name: "Squarespace",
                pageURL: URL(string: "https://status.squarespace.com/")!,
                kind: .statuspage,
                isBuiltIn: true
            ),
            ServiceConfig(
                name: "GitHub",
                pageURL: URL(string: "https://www.githubstatus.com/")!,
                kind: .statuspage,
                isBuiltIn: true
            ),
            ServiceConfig(
                name: "Claude",
                pageURL: URL(string: "https://status.claude.com/")!,
                kind: .statuspage,
                isBuiltIn: true
            ),
            ServiceConfig(
                name: "Slack",
                pageURL: URL(string: "https://slack-status.com/")!,
                kind: .slack,
                isBuiltIn: true
            )
        ]
    }
}
