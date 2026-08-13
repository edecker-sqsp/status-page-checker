import Foundation

/// Errors surfaced by a provider when a page can't be checked or parsed.
/// The message is shown directly in the UI (as the report's description when
/// health == .unknown, or as the rejection reason during service detection),
/// so keep these short and human-readable.
struct ProviderError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Adapts one status-page API shape into a `ServiceReport`.
protocol StatusProvider: Sendable {
    func fetchReport(for config: ServiceConfig, session: URLSession) async throws -> ServiceReport
}

enum HTTPFetch {
    /// Shared timeout for every network call this app makes: checking a
    /// configured service, or probing a candidate URL during detection.
    static let timeout: TimeInterval = 10

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": "StatusChecker/1.0"]
        return URLSession(configuration: configuration)
    }

    /// GETs `url`, ignoring any cached response — a stale cached 200 would
    /// defeat the entire point of polling.
    static func getJSON(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError("Couldn't reach \(url.host ?? url.absoluteString): \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError("No HTTP response from \(url.host ?? url.absoluteString)")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError("\(url.host ?? url.absoluteString) returned HTTP \(http.statusCode)")
        }
        return data
    }
}
