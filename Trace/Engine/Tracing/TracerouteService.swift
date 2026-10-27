import Foundation

struct TraceHop: Identifiable, Codable, Equatable, Sendable {
    let number: Int
    let hostname: String?
    let address: String?
    let latencies: [Double]
    let timeouts: Int
    let annotation: String?
    let raw: String
    var id: Int { number }
    var average: Double? { latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count) }
    var label: String { hostname ?? address ?? "No response" }
}

struct TracerouteParser {
    /// A successful utility exit only means the probe run ended. Require an answering
    /// final hop matching the actual numeric target before saying it was reached.
    static func reachedDestination(output: String, destination: String) -> Bool {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let target: IPAddress?
        if let numeric = IPAddress(destination) { target = numeric }
        else if let header = lines.first(where: { $0.hasPrefix("traceroute to ") || $0.hasPrefix("traceroute6 to ") }),
                let open = header.firstIndex(of: "("), let close = header[open...].firstIndex(of: ")") {
            target = IPAddress(String(header[header.index(after: open)..<close]))
        } else { target = nil }
        guard let target, let last = lines.compactMap(parse).last,
              last.annotation == nil, let address = last.address else { return false }
        return IPAddress(address)?.canonical == target.canonical
    }

    static func parse(_ line: String) -> TraceHop? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, let hop = Int(first), (1...64).contains(hop), tokens.count > 1 else { return nil }
        var address: String?, hostname: String?
        var latencies: [Double] = []
        for index in 1..<tokens.count {
            let token = tokens[index]
            if index + 1 < tokens.count, tokens[index + 1] == "ms", let latency = Double(token) { latencies.append(latency); continue }
            if token == "ms" || token == "*" || token.hasPrefix("!") { continue }
            let candidate = token.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            var ipv4 = in_addr(), ipv6 = in6_addr()
            if inet_pton(AF_INET, candidate, &ipv4) == 1 || inet_pton(AF_INET6, candidate, &ipv6) == 1 {
                if address == nil { address = candidate }
            } else if hostname == nil && Double(token) == nil { hostname = candidate }
        }
        return TraceHop(number: hop, hostname: hostname, address: address, latencies: latencies,
                        timeouts: tokens.filter { $0 == "*" }.count,
                        annotation: tokens.first { $0.hasPrefix("!") }, raw: line)
    }
}

struct TracerouteService: Sendable {
    func trace(destination: String, maxHops: Int, wait: Int, resolveNames: Bool,
               onLine: @escaping @Sendable (String) async -> Void) async throws -> CommandResult {
        let host = try TraceDestination.validate(destination)
        guard (1...64).contains(maxHops), (1...5).contains(wait) else { throw InspectorError.invalidInput("Use 1–64 hops and a 1–5 second probe timeout.") }
        var arguments = ["-m", "\(maxHops)", "-w", "\(wait)", "-q", "1"]
        if !resolveNames { arguments.append("-n") }
        arguments.append(host)
        return try await CommandRunner.run(host.contains(":") ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute",
                                           arguments, timeout: Double(maxHops * wait + 20), onLine: onLine)
    }
}
