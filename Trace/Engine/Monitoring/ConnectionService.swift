import Foundation

struct LsofParser {
    static func parse(_ output: String, at date: Date = .now) -> [Connection] {
        var pid = 0, process = "Unknown", descriptor = "", transport = "", endpoint = "", state = ""
        var rows: [String: Connection] = [:]
        func flush() {
            guard pid > 0, !descriptor.isEmpty, !endpoint.isEmpty, ["TCP", "UDP"].contains(transport) else { return }
            let parts = endpoint.components(separatedBy: "->")
            let connection = Connection(pid: pid, process: process, descriptor: descriptor, transport: transport,
                                        local: .parse(parts[0]), remote: parts.count > 1 ? .parse(parts[1]) : nil,
                                        state: state.isEmpty ? (transport == "UDP" ? "DATAGRAM" : "UNKNOWN") : state,
                                        observedAt: date)
            rows[connection.id] = connection
        }
        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p": flush(); pid = Int(value) ?? 0; process = "Unknown"; descriptor = ""; transport = ""; endpoint = ""; state = ""
            case "c": process = value
            case "f": flush(); descriptor = value; transport = ""; endpoint = ""; state = ""
            case "P": transport = value
            case "n": endpoint = value
            case "T": if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: break
            }
        }
        flush()
        return rows.values.sorted { $0.id < $1.id }
    }
}

struct ConnectionService: Sendable {
    @concurrent
    func snapshot() async throws -> [Connection] {
        let result = try await CommandRunner.run("/usr/sbin/lsof", ["-nP", "-i", "-FpcfPnT"], timeout: 12)
        let rows = LsofParser.parse(result.output)
        guard result.status == 0 || (result.status == 1 && result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            throw InspectorError.command("Socket inspection failed (\(result.status)). \(result.output.prefix(500))")
        }
        return rows
    }
}
