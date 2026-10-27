import Foundation

struct DiagnosticCheck: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let succeeded: Bool
}

struct DiagnosticReport: Codable, Sendable {
    let date: Date
    let destination: String
    let checks: [DiagnosticCheck]
    var text: String { checks.map { "\($0.title): \($0.value)\n\($0.detail)" }.joined(separator: "\n\n") }
}

struct PingSummary: Equatable {
    let loss: Double
    let average: Double?
    static func parse(_ text: String) -> PingSummary? {
        var loss: Double?, average: Double?
        for line in text.split(whereSeparator: \.isNewline) {
            if let range = line.range(of: "% packet loss") {
                loss = line[..<range.lowerBound].split(whereSeparator: { $0 == " " || $0 == "," }).last.flatMap { Double($0) }
            }
            if line.contains("min/avg/max"), let equal = line.firstIndex(of: "=") {
                let parts = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces).split(separator: "/")
                if parts.count >= 2 { average = Double(parts[1]) }
            }
        }
        return loss.map { PingSummary(loss: $0, average: average) }
    }
}

struct DiagnosticsService: Sendable {
    private func command(_ path: String, _ args: [String], title: String, id: String) async throws -> DiagnosticCheck {
        do {
            let result = try await CommandRunner.run(path, args, timeout: 12)
            return DiagnosticCheck(id: id, title: title, value: result.status == 0 ? "Available" : "Unavailable",
                                   detail: result.output, succeeded: result.status == 0)
        } catch is CancellationError { throw CancellationError() }
        catch { return DiagnosticCheck(id: id, title: title, value: "Unavailable", detail: error.localizedDescription, succeeded: false) }
    }

    func run(destination: String) async throws -> DiagnosticReport {
        let host = try TraceDestination.validate(destination)
        async let route = command("/sbin/route", ["-n", "get", "default"], title: "Default route & gateway", id: "route")
        async let dns = command("/usr/sbin/scutil", ["--dns"], title: "System DNS configuration", id: "dns")
        async let connectivity = https(host)
        async let latency = ping(host)
        async let resolution = resolve(host)
        return try await DiagnosticReport(date: .now, destination: host, checks: [connectivity, resolution, latency, route, dns])
    }

    private func https(_ host: String) async throws -> DiagnosticCheck {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.contains(":") ? "[\(host)]" : host
        components.path = "/"
        guard let url = components.url else { throw InspectorError.invalidInput("Cannot form an HTTPS diagnostic URL.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = ContinuousClock.now
        do {
            let (_, response) = try await session.data(for: request)
            try Task.checkCancellation()
            let duration = start.duration(to: .now)
            let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
            let code = (response as? HTTPURLResponse)?.statusCode
            return DiagnosticCheck(id: "https", title: "HTTPS connectivity", value: String(format: "%.0f ms", milliseconds),
                                   detail: "HEAD request to \(url.absoluteString). HTTP status: \(code.map(String.init) ?? "unavailable"). Includes DNS, TCP, TLS and server time; redirects may be followed. Any HTTP response proves connectivity to that endpoint, not the entire internet.", succeeded: code != nil)
        } catch {
            try Task.checkCancellation()
            return DiagnosticCheck(id: "https", title: "HTTPS connectivity", value: "Unavailable", detail: "HEAD \(url.absoluteString)\n\(error.localizedDescription)\nA failed HTTPS check may reflect destination policy or TLS configuration.", succeeded: false)
        }
    }

    private func ping(_ host: String) async throws -> DiagnosticCheck {
        let check = try await command(host.contains(":") ? "/sbin/ping6" : "/sbin/ping",
                                      ["-n", "-c", "4", host], title: "Round-trip latency & loss", id: "ping")
        let summary = PingSummary.parse(check.detail)
        let value = summary.map { summary in
            let latency = summary.average.map { String(format: "%.1f ms", $0) } ?? "No replies"
            return "\(latency) · \(Int(summary.loss))% loss"
        } ?? check.value
        return DiagnosticCheck(id: "ping", title: check.title, value: value,
                               detail: "Four ICMP probes. A blocked probe does not prove internet access is unavailable.\n\n" + check.detail,
                               succeeded: summary.map { $0.loss < 100 } ?? false)
    }

    private func resolve(_ host: String) async throws -> DiagnosticCheck {
        let clock = ContinuousClock(), start = ContinuousClock.now
        let check = try await command("/usr/bin/dscacheutil", ["-q", "host", "-a", "name", host], title: "System resolver lookup", id: "resolve")
        let elapsed = start.duration(to: clock.now)
        let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        let found = check.succeeded && (check.detail.contains("ip_address:") || check.detail.contains("ipv6_address:"))
        return DiagnosticCheck(id: "resolve", title: check.title,
                               value: found ? String(format: "%.0f ms", milliseconds) : "No answer",
                               detail: "Includes utility startup and may use the local DNS cache; this is not resolver wire latency.\n\n" + check.detail,
                               succeeded: found)
    }
}
