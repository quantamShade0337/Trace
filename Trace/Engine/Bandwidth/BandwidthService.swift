import Foundation
import Darwin

struct InterfaceCounter: Identifiable, Sendable, Equatable {
    let name: String
    let received: UInt64
    let sent: UInt64
    let isUp: Bool
    let isPhysical: Bool
    var id: String { name }
}

struct CounterSnapshot: Sendable {
    let date: Date
    let uptime: TimeInterval
    let interfaces: [InterfaceCounter]
}

struct BandwidthSample: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let download: Double
    let upload: Double
    let interfaces: [String]
}

struct BandwidthCalculator {
    static func rate(from previous: CounterSnapshot, to current: CounterSnapshot, selection: String?) -> BandwidthSample? {
        let elapsed = current.uptime - previous.uptime
        guard elapsed >= 0.25, elapsed < 10 else { return nil }
        let old = Dictionary(uniqueKeysWithValues: previous.interfaces.map { ($0.name, $0) })
        let selected = current.interfaces.filter { $0.isUp && (selection == nil ? $0.isPhysical : $0.name == selection) }
        // A changed interface set starts a new baseline instead of introducing a false spike.
        let previousNames = previous.interfaces.filter { $0.isUp && (selection == nil ? $0.isPhysical : $0.name == selection) }.map(\.name).sorted()
        guard !selected.isEmpty, selected.map(\.name).sorted() == previousNames else { return nil }
        var down = 0.0, up = 0.0
        for interface in selected {
            guard let before = old[interface.name], interface.received >= before.received, interface.sent >= before.sent else { return nil }
            down += Double(interface.received - before.received)
            up += Double(interface.sent - before.sent)
        }
        return BandwidthSample(date: current.date, download: down / elapsed, upload: up / elapsed, interfaces: selected.map(\.name).sorted())
    }
}

actor BandwidthService {
    private var previous: CounterSnapshot?
    func reset() { previous = nil }
    func sample(selection: String?) throws -> (CounterSnapshot, BandwidthSample?) {
        let current = try Self.readCounters()
        defer { previous = current }
        return (current, previous.flatMap { BandwidthCalculator.rate(from: $0, to: current, selection: selection) })
    }

    static func readCounters() throws -> CounterSnapshot {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { throw InspectorError.command("Interface counters unavailable (errno \(errno)).") }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0 else { throw InspectorError.command("Interfaces changed while sampling. Retry on the next sample.") }
        var interfaces: [InterfaceCounter] = []
        bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset + 4 <= size {
                let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { break }
                if raw[offset + 3] == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                        let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        interfaces.append(InterfaceCounter(name: name, received: message.ifm_data.ifi_ibytes,
                                                           sent: message.ifm_data.ifi_obytes,
                                                           isUp: message.ifm_flags & IFF_UP != 0 && message.ifm_flags & IFF_RUNNING != 0,
                                                           isPhysical: name.hasPrefix("en") && message.ifm_data.ifi_type == UInt8(IFT_ETHER)))
                    }
                }
                offset += length
            }
        }
        return CounterSnapshot(date: .now, uptime: ProcessInfo.processInfo.systemUptime, interfaces: interfaces.sorted { $0.name < $1.name })
    }
}
