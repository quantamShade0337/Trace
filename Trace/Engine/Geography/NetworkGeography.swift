import Foundation
import Darwin

/// Numeric addresses only. Non-public ranges never leave the Mac for geolocation.
struct IPAddress: Hashable, Sendable {
    let canonical: String
    let isPublic: Bool

    init?(_ input: String) {
        guard !input.isEmpty, input.utf8.count <= 45, input.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 58 || $0 == 46
        }) else { return nil }
        var v4 = in_addr(), v6 = in6_addr()
        var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if inet_pton(AF_INET, input, &v4) == 1 {
            guard inet_ntop(AF_INET, &v4, &output, socklen_t(output.count)) != nil else { return nil }
            let n = UInt32(bigEndian: v4.s_addr)
            let a = n >> 24, b = (n >> 16) & 255, c = (n >> 8) & 255
            isPublic = !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254) ||
                (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) ||
                (a == 192 && b == 0 && (c == 0 || c == 2)) ||
                (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) ||
                (a == 203 && b == 0 && c == 113) || (a == 192 && b == 88 && c == 99))
        } else if inet_pton(AF_INET6, input, &v6) == 1 {
            guard inet_ntop(AF_INET6, &v6, &output, socklen_t(output.count)) != nil else { return nil }
            let bytes = withUnsafeBytes(of: v6) { Array($0) }
            // Only ordinary global unicast (2000::/3), excluding documentation, Teredo,
            // benchmarking, ORCHID and 6to4 ranges that may conceal a private address.
            isPublic = bytes[0] & 0xe0 == 0x20 &&
                !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2) &&
                !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) &&
                !(bytes[0] == 0x20 && bytes[1] == 0x02) &&
                !(bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] < 0x10)
        } else { return nil }
        canonical = String(decoding: output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

struct GeoCoordinate: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

struct IPLocation: Codable, Equatable, Sendable {
    let ip: String
    let coordinate: GeoCoordinate
    let city: String
    let country: String
    let countryCode: String
    let organization: String
    let fetchedAt: Date
    var place: String { city.isEmpty ? country : "\(city), \(country)" }

    static func decode(_ data: Data, expectedIP: String?, at date: Date = .now) throws -> IPLocation {
        struct Response: Decodable {
            struct Connection: Decodable { let isp: String?; let org: String? }
            let success: Bool
            let ip: String?
            let message: String?
            let latitude: Double?
            let longitude: Double?
            let city: String?
            let country: String?
            let country_code: String?
            let connection: Connection?
        }
        let value = try JSONDecoder().decode(Response.self, from: data)
        guard value.success else { throw InspectorError.command(value.message ?? "Location provider could not locate this address.") }
        guard let rawIP = value.ip, let address = IPAddress(rawIP), address.isPublic,
              expectedIP == nil || IPAddress(expectedIP ?? "")?.canonical == address.canonical,
              let latitude = value.latitude, let longitude = value.longitude,
              let country = value.country, !country.isEmpty else {
            throw InspectorError.command("Location provider returned incomplete or mismatched data.")
        }
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else { throw InspectorError.command("Location provider returned invalid coordinates.") }
        return IPLocation(ip: address.canonical, coordinate: coordinate, city: String((value.city ?? "").prefix(120)),
                          country: String(country.prefix(120)), countryCode: String((value.country_code ?? "").prefix(2)),
                          organization: String((value.connection?.org ?? value.connection?.isp ?? "").prefix(160)), fetchedAt: date)
    }
}

struct RemoteDestination: Identifiable, Sendable {
    let host: String
    let connections: [Connection]
    var id: String { host }
    var count: Int { connections.count }
    var processNames: [String] { Array(Set(connections.map(\.process))).sorted() }
    var isPublic: Bool { IPAddress(host)?.isPublic ?? false }
    static func group(_ rows: [Connection]) -> [RemoteDestination] {
        let remote = rows.filter { $0.remote != nil && $0.remote?.host != "*" }
        return Dictionary(grouping: remote, by: { IPAddress($0.remote?.host ?? "")?.canonical ?? $0.remote?.host ?? "" })
            .map { RemoteDestination(host: $0.key, connections: $0.value) }
            .sorted { $0.count == $1.count ? $0.host < $1.host : $0.count > $1.count }
    }
}

struct GeographicSegment: Equatable, Sendable {
    let from: String
    let to: String
    let start: GeoCoordinate
    let end: GeoCoordinate

    /// Never implies a route through an unlocated or timed-out hop.
    static func trace(hops: [TraceHop], locations: [String: IPLocation]) -> [GeographicSegment] {
        let sorted = hops.sorted { $0.number < $1.number }
        return zip(sorted, sorted.dropFirst()).compactMap { first, second in
            guard second.number == first.number + 1,
                  let a = first.address.flatMap(IPAddress.init), let b = second.address.flatMap(IPAddress.init),
                  let start = locations[a.canonical], let end = locations[b.canonical] else { return nil }
            return GeographicSegment(from: a.canonical, to: b.canonical, start: start.coordinate, end: end.coordinate)
        }
    }
}

enum GeoLookupError: LocalizedError, Sendable {
    case rateLimited
    var errorDescription: String? { "The location provider’s request limit was reached. Try again later." }
}

actor IPGeolocationService {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: config, delegate: LocationRedirectPolicy(), delegateQueue: nil)
        }
    }

    /// Invoked only by an explicitly disclosed user action. nil requests the current public exit IP.
    func locate(_ input: String?) async throws -> IPLocation {
        try Task.checkCancellation()
        var address: String?
        if let input {
            guard let parsed = IPAddress(input), parsed.isPublic else { throw InspectorError.invalidInput("Private, local and reserved addresses stay on this Mac.") }
            address = parsed.canonical
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ipwho.is"
        components.path = "/" + (address ?? "")
        components.queryItems = [URLQueryItem(name: "fields", value: "success,message,ip,latitude,longitude,city,country,country_code,connection.org,connection.isp")]
        guard let url = components.url else { throw InspectorError.invalidInput("Cannot create the location lookup.") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("IPLocationLookup/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        if (response as? HTTPURLResponse)?.statusCode == 429 { throw GeoLookupError.rateLimited }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.url?.host == "ipwho.is" else {
            throw InspectorError.command("The location provider is unavailable. Your network monitoring is still running.")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw InspectorError.outputLimit }
            data.append(byte)
        }
        return try IPLocation.decode(data, expectedIP: address)
    }
}

/// Location consent is scoped to this provider; never follow a redirect to another service.
private final class LocationRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
