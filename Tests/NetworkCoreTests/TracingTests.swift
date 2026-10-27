import Foundation
import Testing
@testable import NetworkCore

struct TracingTests {
    @Test func parsesNumericNamedAndTimeoutHops() throws {
        let numeric = try #require(TracerouteParser.parse(" 1  192.0.2.1  1.200 ms"))
        #expect(numeric.address == "192.0.2.1")
        #expect(numeric.average == 1.2)
        let named = try #require(TracerouteParser.parse(" 2 router.example (2001:db8::2)  3.5 ms  4.5 ms !H"))
        #expect(named.hostname == "router.example")
        #expect(named.address == "2001:db8::2")
        #expect(named.average == 4)
        #expect(named.annotation == "!H")
        let timeout = try #require(TracerouteParser.parse("3 * * *"))
        #expect(timeout.address == nil)
        #expect(timeout.timeouts == 3)
        #expect(timeout.average == nil)
        #expect(TracerouteParser.parse("traceroute to example.com") == nil)
    }
    @Test(arguments: ["-m", "example.com;whoami", "example.com\nfoo", "https://example.com", "example.com/path", "example.com:443", "$(id)", "::bad::"])
    func rejectsCommandInjectionAndMalformedHosts(_ input: String) {
        #expect(throws: InspectorError.self) { try TraceDestination.validate(input) }
    }
    @Test func acceptsIPVersionsAndHostnames() throws {
        #expect(try TraceDestination.validate("2001:db8::1") == "2001:db8::1")
        #expect(try TraceDestination.validate("127.0.0.1") == "127.0.0.1")
        #expect(try TraceDestination.validate("EXAMPLE.COM.") == "example.com")
    }
    @Test func childProcessTimeoutIsBounded() async {
        await #expect(throws: InspectorError.self) { try await CommandRunner.run("/bin/sleep", ["3"], timeout: 0.12) }
    }
    @Test func cancellingChildProcessStopsPromptly() async throws {
        let task = Task { try await CommandRunner.run("/bin/sleep", ["10"]) }
        try await Task.sleep(for: .milliseconds(120))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: .now) < .seconds(2))
    }
    @Test func capturesOutputAndNonzeroExit() async throws {
        let result = try await CommandRunner.run("/usr/bin/false", [])
        #expect(result.status != 0)
        await #expect(throws: (any Error).self) { try await CommandRunner.run("/nonexistent/utility", []) }
    }
    @Test func completionRequiresTheActualDestinationToRespond() {
        let header = "traceroute to example.com (93.184.215.14), 30 hops max, 52 byte packets\n"
        #expect(TracerouteParser.reachedDestination(output: header + "1 93.184.215.14 2.5 ms", destination: "example.com"))
        #expect(!TracerouteParser.reachedDestination(output: header + "1 192.168.1.1 2.5 ms\n2 *", destination: "example.com"))
        #expect(!TracerouteParser.reachedDestination(output: header + "1 93.184.215.14 2.5 ms !H", destination: "example.com"))
        #expect(!TracerouteParser.reachedDestination(output: "1 *", destination: "1.1.1.1"))
        #expect(TracerouteParser.reachedDestination(output: "1 0:0:0:0:0:0:0:1 0.01 ms", destination: "::1"))
        #expect(TracerouteParser.reachedDestination(output: "traceroute6 to localhost (::1) from ::1, 2 hops max\n1 ::1 0.01 ms", destination: "localhost"))
    }
    @Test func loopbackTraceUsesRealProbe() async throws {
        let result = try await TracerouteService().trace(destination: "127.0.0.1", maxHops: 2, wait: 1, resolveNames: false) { _ in }
        #expect(result.status == 0)
        let hops = result.output.split(whereSeparator: \.isNewline).compactMap { TracerouteParser.parse(String($0)) }
        #expect(hops.first?.address == "127.0.0.1")
        #expect(hops.first?.average != nil)
    }
    @Test func loopbackIPv6TraceUsesRealProbe() async throws {
        let result = try await TracerouteService().trace(destination: "::1", maxHops: 2, wait: 1, resolveNames: false) { _ in }
        #expect(result.status == 0)
        #expect(result.output.split(whereSeparator: \.isNewline).compactMap { TracerouteParser.parse(String($0)) }.first?.address == "::1")
    }
    @Test func outputLimitStopsNoisyChild() async {
        await #expect(throws: InspectorError.self) { try await CommandRunner.run("/usr/bin/yes", ["x"], timeout: 3) }
    }
    @Test func pingSummaryReportsLossAndLatency() throws {
        let summary = try #require(PingSummary.parse("4 packets transmitted, 3 packets received, 25.0% packet loss\nround-trip min/avg/max/stddev = 1.1/2.2/3.3/0.5 ms"))
        #expect(summary.loss == 25)
        #expect(summary.average == 2.2)
        #expect(PingSummary.parse("ping: cannot resolve host") == nil)
    }
}
