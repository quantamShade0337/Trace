import Foundation
import Testing
@testable import NetworkCore

/// Immutable request-driven fixtures. No shared mutable state and no network access.
private final class FixtureLocationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "ipwho.is" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let status: Int
        let data: Data
        switch url.path {
        case "/1.1.1.1": status = 429; data = Data()
        case "/9.9.9.9": status = 200; data = Data(repeating: 120, count: 70_000)
        case "/4.4.4.4": status = 503; data = Data()
        default:
            status = 200
            data = Data(#"{"success":true,"ip":"8.8.8.8","latitude":37.3,"longitude":-122.1,"city":"Fixture city","country":"Fixture country","country_code":"XX"}"#.utf8)
        }
        if let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

struct GeolocationServiceTests {
    private func service() -> IPGeolocationService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureLocationProtocol.self]
        return IPGeolocationService(session: URLSession(configuration: config))
    }
    @Test func parsesARealisticResponseWithoutNetworking() async throws {
        let result = try await service().locate("8.8.8.8")
        #expect(result.city == "Fixture city")
        #expect(result.ip == "8.8.8.8")
    }
    @Test func rateLimitAndProviderErrorsAreExplicit() async {
        await #expect(throws: GeoLookupError.self) { try await service().locate("1.1.1.1") }
        await #expect(throws: InspectorError.self) { try await service().locate("4.4.4.4") }
    }
    @Test func responseBodiesAreBounded() async {
        await #expect(throws: InspectorError.self) { try await service().locate("9.9.9.9") }
    }
    @Test func cancellationBeforeLookupPreventsRequests() async {
        let service = service()
        let task = Task {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
            return try await service.locate("8.8.8.8")
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
