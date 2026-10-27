import Foundation
import Darwin

struct DomainName {
    static func normalize(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }),
              !value.contains(where: { "/:@?#%\\[]".contains($0) }),
              let url = URL(string: "https://\(value)"), let host = url.host(percentEncoded: false) else {
            throw InspectorError.invalidInput("Enter a domain name without a scheme, path, port, or wildcard.")
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { throw InspectorError.invalidInput("The domain name is not valid. Check its labels and length.") }
        return host
    }
}

struct TraceDestination {
    static func validate(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var ipv4 = in_addr(), ipv6 = in6_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 || inet_pton(AF_INET6, value, &ipv6) == 1 { return value }
        guard !value.hasPrefix("-"), !value.contains("\n") else { throw InspectorError.invalidInput("Enter a hostname or IP address.") }
        return try DomainName.normalize(value)
    }
}

enum FilterDecision: Equatable, Sendable {
    case allowed(rule: String?)
    case blocked(rule: String)
}

struct DomainFilter: Sendable {
    let allow: Set<String>
    let block: Set<String>

    /// Parse hosts-format and plain-domain lists atomically. Invalid lines abort the update.
    static func parseRules(_ text: String) throws -> Set<String> {
        guard text.utf8.count <= 1_048_576 else { throw InspectorError.invalidInput("Rule lists are limited to 1 MB.") }
        var rules = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            var tokens = content.split(whereSeparator: \.isWhitespace).map(String.init)
            if tokens.isEmpty { continue }
            if ["0.0.0.0", "127.0.0.1", "::", "::1"].contains(tokens[0]) { tokens.removeFirst() }
            for token in tokens { rules.insert(try DomainName.normalize(token)) }
        }
        guard rules.count <= 50_000 else { throw InspectorError.invalidInput("Use no more than 50,000 rules per list.") }
        return rules
    }

    func evaluate(_ input: String) throws -> FilterDecision {
        let domain = try DomainName.normalize(input)
        let labels = domain.split(separator: ".")
        let candidates = labels.indices.map { labels[$0...].joined(separator: ".") }
        // Explicit allow rules (including parent rules) always win over block rules.
        if let rule = candidates.first(where: allow.contains) { return .allowed(rule: rule) }
        if let rule = candidates.first(where: block.contains) { return .blocked(rule: rule) }
        return .allowed(rule: nil)
    }
}

struct ProtectionProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var allowlist: String
    var blocklist: String
    static let defaults = [
        ProtectionProfile(id: "standard", name: "Standard", allowlist: "", blocklist: ""),
        ProtectionProfile(id: "privacy", name: "Privacy", allowlist: "", blocklist: ""),
        ProtectionProfile(id: "strict", name: "Strict", allowlist: "", blocklist: "")
    ]
    func engine() throws -> DomainFilter {
        try DomainFilter(allow: DomainFilter.parseRules(allowlist), block: DomainFilter.parseRules(blocklist))
    }
}
