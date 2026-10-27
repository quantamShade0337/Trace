import Foundation
import Testing
@testable import NetworkCore

struct GeographyTests {
    @Test(arguments: ["0.0.0.0", "10.1.2.3", "127.0.0.1", "169.254.8.8", "100.64.0.1", "100.127.255.255", "172.16.0.1", "172.31.255.1", "192.168.1.1", "192.0.2.5", "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255", "::", "::1", "fe80::1", "fc00::1", "ff02::1", "::ffff:192.168.0.1", "2001:db8::1", "2002:0a01:0203::1", "2001:20::1", "3fff::1"])
    func nonPublicAddressesNeverLeaveTheMac(_ address: String) throws {
        #expect(try #require(IPAddress(address)).isPublic == false)
    }
    @Test(arguments: ["8.8.8.8", "1.1.1.1", "172.32.0.1", "100.128.0.1", "17.248.0.1", "2001:4860:4860::8888", "2606:4700:4700::1111"])
    func acceptsPublicAddresses(_ address: String) throws {
        #expect(try #require(IPAddress(address)).isPublic)
    }
    @Test func numericValidationAndIPv6Canonicalization() {
        #expect(IPAddress("2001:4860:4860:0:0:0:0:8888")?.canonical == "2001:4860:4860::8888")
        #expect(IPAddress("example.com") == nil)
        #expect(IPAddress("1.1.1.1/path") == nil)
        #expect(IPAddress("fe80::1%en0") == nil)
    }
    private func location(_ ip: String, lat: Double = 20, lon: Double = 30) -> IPLocation {
        IPLocation(ip: ip, coordinate: GeoCoordinate(latitude: lat, longitude: lon), city: "Fixture city", country: "Fixture country", countryCode: "XX", organization: "Fixture", fetchedAt: .now)
    }
    private func hop(_ number: Int, _ address: String?) -> TraceHop {
        TraceHop(number: number, hostname: nil, address: address, latencies: [], timeouts: address == nil ? 1 : 0, annotation: nil, raw: "fixture")
    }
    @Test func geographicTraceDoesNotBridgeUnknownHops() {
        let locations = ["1.1.1.1": location("1.1.1.1"), "8.8.8.8": location("8.8.8.8", lat: 40)]
        #expect(GeographicSegment.trace(hops: [hop(1, "1.1.1.1"), hop(2, nil), hop(3, "8.8.8.8")], locations: locations).isEmpty)
        #expect(GeographicSegment.trace(hops: [hop(1, "1.1.1.1"), hop(3, "8.8.8.8")], locations: locations).isEmpty)
        #expect(GeographicSegment.trace(hops: [hop(1, "1.1.1.1"), hop(2, "8.8.8.8")], locations: locations).count == 1)
        #expect(GeographicSegment.trace(hops: [hop(1, "1.1.1.1"), hop(2, "8.8.8.8")], locations: [:]).isEmpty)
    }
    @Test func providerResponsesValidateIdentityAndCoordinates() throws {
        let data = Data(#"{"success":true,"ip":"8.8.8.8","latitude":37.3,"longitude":-122.1,"city":"Fixture city","country":"Fixture country","country_code":"XX","connection":{"org":"Fixture"}}"#.utf8)
        let decoded = try IPLocation.decode(data, expectedIP: "8.8.8.8", at: .distantPast)
        #expect(decoded.coordinate.isValid)
        #expect(decoded.organization == "Fixture")
        #expect(decoded.fetchedAt == .distantPast)
        #expect(throws: InspectorError.self) { try IPLocation.decode(data, expectedIP: "1.1.1.1") }
        let invalid = Data(#"{"success":true,"ip":"8.8.8.8","latitude":999,"longitude":10,"country":"Fixture"}"#.utf8)
        #expect(throws: InspectorError.self) { try IPLocation.decode(invalid, expectedIP: nil) }
        let privateIP = Data(#"{"success":true,"ip":"127.0.0.1","latitude":20,"longitude":10,"country":"Fixture"}"#.utf8)
        #expect(throws: InspectorError.self) { try IPLocation.decode(privateIP, expectedIP: nil) }
        let failure = Data(#"{"success":false,"message":"Reserved range"}"#.utf8)
        #expect(throws: InspectorError.self) { try IPLocation.decode(failure, expectedIP: nil) }
    }
    @Test func serviceRejectsLocalAddressesBeforeNetworking() async {
        await #expect(throws: InspectorError.self) { try await IPGeolocationService().locate("192.168.0.1") }
        await #expect(throws: InspectorError.self) { try await IPGeolocationService().locate("localhost") }
    }
    @Test func remoteGroupingKeepsAllObservedConnections() {
        let date = Date.now
        let a = Connection(pid: 1, process: "App A", descriptor: "1", transport: "TCP", local: .init(host: "10.0.0.1", port: "1"), remote: .init(host: "8.8.8.8", port: "443"), state: "ESTABLISHED", observedAt: date)
        let b = Connection(pid: 2, process: "App B", descriptor: "2", transport: "UDP", local: a.local, remote: a.remote, state: "DATAGRAM", observedAt: date)
        let rows = RemoteDestination.group([a, b])
        #expect(rows.count == 1)
        #expect(rows.first?.count == 2)
        #expect(rows.first?.processNames == ["App A", "App B"])
    }
}
