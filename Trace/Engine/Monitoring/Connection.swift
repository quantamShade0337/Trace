import Foundation

struct Endpoint: Codable, Hashable, Sendable {
    let host: String
    let port: String
    var display: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }

    static func parse(_ value: String) -> Endpoint {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard let colon = value.lastIndex(of: ":") else { return Endpoint(host: value, port: "*") }
        let host = String(value[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return Endpoint(host: host, port: String(value[value.index(after: colon)...]))
    }
}

struct Connection: Identifiable, Codable, Hashable, Sendable {
    let pid: Int
    let process: String
    let descriptor: String
    let transport: String
    let local: Endpoint
    let remote: Endpoint?
    let state: String
    let observedAt: Date
    var id: String { "\(pid)|\(descriptor)|\(transport)|\(local.display)|\(remote?.display ?? "")" }
    var remoteDisplay: String { remote?.display ?? "—" }
    var isTraceable: Bool { remote.map { $0.host != "*" && !$0.host.isEmpty } ?? false }
}

struct ProcessSummary: Identifiable, Sendable {
    let pid: Int
    let name: String
    let connections: [Connection]
    var id: Int { pid }
    var count: Int { connections.count }
    static func group(_ connections: [Connection]) -> [ProcessSummary] {
        Dictionary(grouping: connections, by: \.pid).map { pid, rows in
            ProcessSummary(pid: pid, name: rows.first?.process ?? "Unknown", connections: rows)
        }.sorted { $0.count == $1.count ? $0.pid < $1.pid : $0.count > $1.count }
    }
}

enum ConnectionScope: String, CaseIterable, Identifiable {
    case all = "All sockets", established = "Established", listening = "Listening", tcp = "TCP", udp = "UDP"
    var id: String { rawValue }
}

struct ConnectionQuery {
    var text = ""
    var scope = ConnectionScope.all
    func matches(_ connection: Connection) -> Bool {
        let inScope: Bool
        switch scope {
        case .all: inScope = true
        case .established: inScope = connection.state == "ESTABLISHED"
        case .listening: inScope = connection.state == "LISTEN"
        case .tcp: inScope = connection.transport == "TCP"
        case .udp: inScope = connection.transport == "UDP"
        }
        return inScope && (text.isEmpty || "\(connection.process) \(connection.pid) \(connection.local.display) \(connection.remoteDisplay) \(connection.state)".localizedStandardContains(text))
    }
}
