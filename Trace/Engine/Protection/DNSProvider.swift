import Foundation
import NetworkExtension
import Security

struct DNSProvider: Codable, Equatable, Sendable {
    var name: String
    var endpoint: String
    var servers: [String]
    static let cloudflare = DNSProvider(name: "Cloudflare", endpoint: "https://cloudflare-dns.com/dns-query", servers: ["1.1.1.1", "1.0.0.1"])
    static let quad9 = DNSProvider(name: "Quad9", endpoint: "https://dns.quad9.net/dns-query", servers: ["9.9.9.9", "149.112.112.112"])

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 80, endpoint.utf8.count <= 2048,
              let url = URLComponents(string: endpoint), url.scheme == "https", let host = url.host,
              !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil,
              !url.path.isEmpty, url.query == nil else {
            throw InspectorError.invalidInput("Use a named HTTPS resolver URL with a path, without credentials, query parameters, or a fragment.")
        }
        _ = try TraceDestination.validate(host)
        guard !servers.isEmpty, servers.count <= 8 else { throw InspectorError.invalidInput("Provide 1–8 bootstrap server IP addresses.") }
        for address in servers {
            var ipv4 = in_addr(), ipv6 = in6_addr()
            guard inet_pton(AF_INET, address, &ipv4) == 1 || inet_pton(AF_INET6, address, &ipv6) == 1 else {
                throw InspectorError.invalidInput("Bootstrap servers must be numeric IPv4 or IPv6 addresses.")
            }
        }
    }

    /// Builds independent settings only; never saves or changes system configuration.
    func makeSettings() throws -> NEDNSOverHTTPSSettings {
        try validate()
        let settings = NEDNSOverHTTPSSettings(servers: servers)
        settings.serverURL = URL(string: endpoint)
        return settings
    }
}

struct ProtectionCapability: Sendable {
    let hasDNSEntitlement: Bool
    let explanation: String
    static func inspect() -> ProtectionCapability {
        let task = SecTaskCreateFromSelf(nil)
        let values = task.flatMap { SecTaskCopyValueForEntitlement($0, "com.apple.developer.networking.networkextension" as CFString, nil) } as? [String] ?? []
        let entitled = values.contains("dns-settings")
        return ProtectionCapability(hasDNSEntitlement: entitled,
            explanation: entitled
                ? "The DNS settings entitlement is present. System activation is unavailable in this build because preference installation and resolver behaviour have not been verified."
                : "This build has no NetworkExtension dns-settings entitlement. System-wide encrypted DNS requires an appropriately signed build and user approval in macOS. No DNS settings have been changed.")
    }
}
