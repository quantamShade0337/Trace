import Foundation
import Testing
@testable import NetworkCore

struct DiagnosticsTests {
    @Test func loopbackDiagnosticsReturnMeasuredEvidence() async throws {
        let report = try await DiagnosticsService().run(destination: "127.0.0.1")
        #expect(report.checks.count == 5)
        let ping = try #require(report.checks.first { $0.id == "ping" })
        #expect(ping.succeeded)
        #expect(ping.value.contains("0% loss"))
        #expect(ping.detail.contains("4 packets transmitted"))
        #expect(report.checks.contains { $0.id == "dns" && !$0.detail.isEmpty })
        #expect(report.checks.contains { $0.id == "route" && !$0.detail.isEmpty })
        // Loopback need not have a TLS server. Either success or an explicit failure is real evidence.
        #expect(report.checks.contains { $0.id == "https" && !$0.detail.isEmpty })
    }
    @Test func diagnosticCancellationPropagatesAcrossChecks() async throws {
        let task = Task { try await DiagnosticsService().run(destination: "127.0.0.1") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
