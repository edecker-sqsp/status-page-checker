import Foundation

/// Result of probing a user-supplied URL to see whether StatusChecker knows
/// how to monitor it.
enum DetectionOutcome: Equatable {
    case detected(kind: ProviderKind, origin: URL, suggestedName: String)
    case rejected(reason: String)
}

/// Figures out whether a pasted URL is a Statuspage-hosted page, Slack's
/// status page, or something unsupported.
enum ProviderDetector {

    /// Hosts known to run Slack's bespoke (non-Statuspage) status API.
    static let knownSlackHosts: Set<String> = ["slack-status.com", "status.slack.com"]

    static func detect(urlString: String) async -> DetectionOutcome {
        guard let origin = normalizeOrigin(urlString) else {
            return .rejected(reason: "That doesn't look like a valid URL.")
        }

        let session = HTTPFetch.makeSession()

        if let host = origin.host?.lowercased(), knownSlackHosts.contains(host) {
            do {
                let data = try await HTTPFetch.getJSON(SlackProvider.endpointURL(origin: origin), session: session)
                _ = try JSONDecoder().decode(SlackProvider.Current.self, from: data)
                return .detected(kind: .slack, origin: origin, suggestedName: "Slack")
            } catch let error as ProviderError {
                return .rejected(reason: error.description)
            } catch {
                return .rejected(reason: "Couldn't verify Slack's status API at \(origin.host ?? urlString).")
            }
        }

        do {
            let data = try await HTTPFetch.getJSON(StatuspageProvider.summaryURL(origin: origin), session: session)
            let summary = try JSONDecoder().decode(StatuspageProvider.Summary.self, from: data)
            guard !summary.page.name.isEmpty, !summary.status.indicator.isEmpty else {
                return .rejected(reason: "\(origin.host ?? urlString) responded, but not in a recognized shape.")
            }
            return .detected(kind: .statuspage, origin: origin, suggestedName: summary.page.name)
        } catch let error as ProviderError {
            return .rejected(reason: error.description)
        } catch {
            return .rejected(reason: "\(origin.host ?? urlString) doesn't expose a supported status API (Statuspage's /api/v2/summary.json).")
        }
    }

    /// Coerces free-form user input ("status.example.com", "example.com/status",
    /// "https://example.com/") into a bare scheme+host origin.
    static func normalizeOrigin(_ input: String) -> URL? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host
        components.port = url.port
        return components.url
    }
}
