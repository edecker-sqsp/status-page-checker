import Foundation
import Testing
@testable import StatusChecker

struct ProviderDetectorTests {

    @Test func addsHTTPSSchemeWhenMissing() {
        let origin = ProviderDetector.normalizeOrigin("status.example.com")
        #expect(origin?.absoluteString == "https://status.example.com")
    }

    @Test func stripsPathAndQuery() {
        let origin = ProviderDetector.normalizeOrigin("https://status.example.com/history?foo=bar")
        #expect(origin?.absoluteString == "https://status.example.com")
    }

    @Test func preservesExplicitHTTPScheme() {
        let origin = ProviderDetector.normalizeOrigin("http://status.example.com")
        #expect(origin?.scheme == "http")
    }

    @Test func rejectsEmptyOrHostlessInput() {
        #expect(ProviderDetector.normalizeOrigin("") == nil)
        #expect(ProviderDetector.normalizeOrigin("   ") == nil)
        #expect(ProviderDetector.normalizeOrigin("not a url") == nil)
    }

    @Test func recognizesKnownSlackHosts() {
        #expect(ProviderDetector.knownSlackHosts.contains("slack-status.com"))
        #expect(ProviderDetector.knownSlackHosts.contains("status.slack.com"))
    }
}
