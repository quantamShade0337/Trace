import Foundation
import Testing
@testable import NetworkCore

struct MonitoringTests {
    let fixture = """
    p42
    cBrowser Helper
    f12
    PTCP
    n192.0.2.1:50100->203.0.113.20:443
    TST=ESTABLISHED
    f13
    PUDP
    n[::1]:5353
    p87
    cListener
    f4
    PTCP
    n*:8080
    TST=LISTEN
    """

    @Test func fieldParserAssociatesProcessesAndEndpoints() throws {
        let rows = LsofParser.parse(fixture, at: Date(timeIntervalSince1970: 1))
        #expect(rows.count == 3)
        let tcp = try #require(rows.first { $0.pid == 42 && $0.transport == "TCP" })
        #expect(tcp.process == "Browser Helper")
        #expect(tcp.remote == Endpoint(host: "203.0.113.20", port: "443"))
        #expect(tcp.local.port == "50100")
        #expect(tcp.state == "ESTABLISHED")
        #expect(rows.first { $0.descriptor == "13" }?.local.host == "::1")
        #expect(rows.first { $0.pid == 87 }?.remote == nil)
    }

    @Test func malformedAndDuplicateRecords() {
        #expect(LsofParser.parse("garbage\nf4\nPTCP\nn*:80").isEmpty)
        #expect(LsofParser.parse(fixture + "\np42\ncBrowser Helper\nf12\nPTCP\nn192.0.2.1:50100->203.0.113.20:443\nTST=ESTABLISHED").count == 3)
    }

    @Test func identitySurvivesPollingAndStateChanges() throws {
        let before = try #require(LsofParser.parse(fixture).first { $0.transport == "TCP" && $0.pid == 42 })
        let after = try #require(LsofParser.parse(fixture.replacingOccurrences(of: "ESTABLISHED", with: "CLOSE_WAIT"), at: .distantFuture).first { $0.transport == "TCP" && $0.pid == 42 })
        #expect(before.id == after.id)
        let reused = try #require(LsofParser.parse(fixture.replacingOccurrences(of: "203.0.113.20", with: "203.0.113.21")).first { $0.transport == "TCP" && $0.pid == 42 })
        #expect(before.id != reused.id)
    }

    @Test func groupingFilteringAndSort() {
        let rows = LsofParser.parse(fixture)
        let grouped = ProcessSummary.group(rows)
        #expect(grouped.map(\.pid) == [42, 87])
        #expect(grouped[0].count == 2)
        #expect(rows.filter(ConnectionQuery(text: "helper", scope: .established).matches).count == 1)
        #expect(rows.filter(ConnectionQuery(text: "8080", scope: .listening).matches).count == 1)
        #expect(rows.filter(ConnectionQuery(text: "", scope: .udp).matches).count == 1)
        #expect(rows.sorted(using: [KeyPathComparator(\Connection.pid, order: .reverse)]).first?.pid == 87)
    }

    @Test func endpointsHandleIPv6AndWildcards() {
        #expect(Endpoint.parse("[2001:db8::1]:443").host == "2001:db8::1")
        #expect(Endpoint.parse("*:*") == Endpoint(host: "*", port: "*"))
        #expect(Endpoint.parse("[::1]:53").display == "[::1]:53")
    }

    @Test func realSocketInspectionReturnsValidRows() async throws {
        let rows = try await ConnectionService().snapshot()
        #expect(rows.allSatisfy { $0.pid > 0 && !$0.process.isEmpty && !$0.local.host.isEmpty })
    }
}
