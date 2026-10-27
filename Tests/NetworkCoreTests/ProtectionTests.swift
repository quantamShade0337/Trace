import Foundation
import Testing
@testable import NetworkCore

struct ProtectionTests {
    @Test func domainsNormalizeAndDeduplicate() throws {
        #expect(try DomainName.normalize(" Example.COM. ") == "example.com")
        #expect(try DomainName.normalize("bücher.de") == "xn--bcher-kva.de")
        #expect(try DomainFilter.parseRules("# comment\n0.0.0.0 Example.com ads.example.com # hosts\nexample.com\n") == ["example.com", "ads.example.com"])
    }
    @Test(arguments: ["", "a..com", "-a.com", "a-.com", "https://example.com", "a.com/path", "*.example.com", "a.com:80", "a com"])
    func rejectsInvalidDomains(_ value: String) { #expect(throws: InspectorError.self) { try DomainName.normalize(value) } }
    @Test func allowRulesOverrideBlocksIncludingParents() throws {
        let engine = DomainFilter(allow: ["safe.example.com"], block: ["example.com"])
        #expect(try engine.evaluate("ads.example.com") == .blocked(rule: "example.com"))
        #expect(try engine.evaluate("safe.example.com") == .allowed(rule: "safe.example.com"))
        #expect(try engine.evaluate("child.safe.example.com") == .allowed(rule: "safe.example.com"))
        #expect(try engine.evaluate("notexample.com") == .allowed(rule: nil))
    }
    @Test func invalidUpdatesLeavePreviousEngineUsable() throws {
        let profile = ProtectionProfile(id: "test", name: "Test", allowlist: "", blocklist: "example.com")
        let engine = try profile.engine()
        #expect(throws: InspectorError.self) { try DomainFilter.parseRules("ads.example.com\ninvalid/path") }
        #expect(try engine.evaluate("example.com") == .blocked(rule: "example.com"))
        let empty = try ProtectionProfile.defaults[0].engine()
        #expect(try empty.evaluate("example.com") == .allowed(rule: nil))
    }
    @Test func providerSettingsAreValidatedWithoutActivation() throws {
        try DNSProvider.cloudflare.validate()
        try DNSProvider.quad9.validate()
        let settings = try DNSProvider.cloudflare.makeSettings()
        #expect(settings.serverURL?.absoluteString == DNSProvider.cloudflare.endpoint)
        #expect(settings.servers == ["1.1.1.1", "1.0.0.1"])
    }
    @Test(arguments: ["http://dns.example/dns-query", "https://user:pass@dns.example/dns-query", "https://dns.example", "https://dns.example/dns-query?token=foo"])
    func providerRejectsUnsafeURLs(_ value: String) {
        #expect(throws: InspectorError.self) { try DNSProvider(name: "Test", endpoint: value, servers: ["1.1.1.1"]).validate() }
    }
    @Test func providerRequiresNumericBootstrapAddresses() {
        #expect(throws: InspectorError.self) { try DNSProvider(name: "Test", endpoint: "https://dns.example/dns-query", servers: ["dns.example"]).validate() }
    }
}
