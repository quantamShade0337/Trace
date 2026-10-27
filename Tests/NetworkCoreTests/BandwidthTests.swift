import Foundation
import Testing
@testable import NetworkCore

struct BandwidthTests {
    func snapshot(_ uptime: Double, _ counters: [InterfaceCounter]) -> CounterSnapshot {
        CounterSnapshot(date: Date(timeIntervalSince1970: uptime), uptime: uptime, interfaces: counters)
    }
    func interface(_ name: String, _ received: UInt64, _ sent: UInt64, physical: Bool = true, up: Bool = true) -> InterfaceCounter {
        InterfaceCounter(name: name, received: received, sent: sent, isUp: up, isPhysical: physical)
    }
    func interface(_ received: UInt64, _ sent: UInt64) -> InterfaceCounter { interface("en0", received, sent) }
    @Test func ratesUseElapsedTimeAndIgnoreVirtualInterfaces() throws {
        let a = snapshot(10, [interface(1000, 500), interface("utun0", 1000, 1000, physical: false)])
        let b = snapshot(12, [interface(3000, 1500), interface("utun0", 99999, 99999, physical: false)])
        let rate = try #require(BandwidthCalculator.rate(from: a, to: b, selection: nil))
        #expect(rate.download == 1000)
        #expect(rate.upload == 500)
        #expect(rate.interfaces == ["en0"])
        #expect(BandwidthCalculator.rate(from: a, to: b, selection: "utun0")?.download == 49499.5)
    }
    @Test func counterResetAndLongInterruptionResetBaseline() {
        let a = snapshot(1, [interface(9000, 400)])
        #expect(BandwidthCalculator.rate(from: a, to: snapshot(2, [interface(100, 500)]), selection: nil) == nil)
        #expect(BandwidthCalculator.rate(from: a, to: snapshot(20, [interface(10000, 500)]), selection: nil) == nil)
        #expect(BandwidthCalculator.rate(from: a, to: a, selection: nil) == nil)
    }
    @Test func interfaceChangesDoNotCreateSpikes() {
        let a = snapshot(1, [interface(100, 100)])
        let b = snapshot(2, [interface(200, 200), interface("en1", 8000, 9000)])
        #expect(BandwidthCalculator.rate(from: a, to: b, selection: nil) == nil)
        #expect(BandwidthCalculator.rate(from: a, to: b, selection: "en0")?.download == 100)
        #expect(BandwidthCalculator.rate(from: a, to: snapshot(2, []), selection: nil) == nil)
    }
    @Test func countersExceed32BitsWithoutTruncation() {
        let a = snapshot(1, [interface(5_000_000_000, 7_000_000_000)])
        let b = snapshot(2, [interface(5_000_001_000, 7_000_000_500)])
        #expect(BandwidthCalculator.rate(from: a, to: b, selection: nil)?.download == 1000)
    }
    @Test func realSamplingProducesCounterDifferences() async throws {
        let service = BandwidthService()
        let (baseline, first) = try await service.sample(selection: "lo0")
        #expect(first == nil)
        #expect(baseline.interfaces.contains { $0.name == "lo0" && $0.isUp })
        try await Task.sleep(for: .milliseconds(300))
        let (_, rate) = try await service.sample(selection: "lo0")
        let measurement = try #require(rate)
        #expect(measurement.download >= 0 && measurement.upload >= 0)
        await service.reset()
        let (_, reset) = try await service.sample(selection: "lo0")
        #expect(reset == nil)
    }
    @Test func realCountersAreUniqueAndReadable() throws {
        let counters = try BandwidthService.readCounters()
        #expect(!counters.interfaces.isEmpty)
        #expect(counters.interfaces.count == Set(counters.interfaces.map(\.name)).count)
    }
}
