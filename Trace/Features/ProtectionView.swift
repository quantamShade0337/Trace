import SwiftUI

struct ProtectionView: View {
    @Bindable var model: ProtectionModel
    @State private var editingResolver = false
    @State private var providerName = ""
    @State private var endpoint = ""
    @State private var servers = ""
    @State private var profileName = ""
    @State private var allow = ""
    @State private var block = ""
    @State private var testDomain = ""
    @State private var result: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(title: "DNS protection", subtitle: "Choose how domain lookups should be handled.")
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "shield.slash").font(.system(size: 31, weight: .light)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protection isn’t available in this build").font(.system(size: 17, weight: .semibold))
                        Text("You can prepare a resolver and test custom rules here. These settings aren’t applied to your Mac’s DNS traffic.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Unavailable", systemImage: "shield.slash") {}.disabled(true)
                }.padding(.vertical, 10)
                DisclosureGroup("Why can’t I enable protection?") {
                    Text(model.capability.explanation).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Encrypted DNS resolver").font(.system(size: 14, weight: .semibold))
                            Text("Saved locally: \(model.provider.name)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu("Choose provider") {
                            Button("Cloudflare") { fillProvider(.cloudflare); editingResolver = true }
                            Button("Quad9") { fillProvider(.quad9); editingResolver = true }
                        }
                    }
                    DisclosureGroup("Edit resolver configuration", isExpanded: $editingResolver) {
                        VStack(alignment: .leading, spacing: 16) {
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                                GridRow { Text("Provider name").foregroundStyle(.secondary); TextField("Name", text: $providerName) }
                                GridRow { Text("HTTPS endpoint").foregroundStyle(.secondary); TextField("https://resolver.example/dns-query", text: $endpoint).font(.system(.body, design: .monospaced)) }
                                GridRow { Text("Server IPs").foregroundStyle(.secondary); TextField("Comma-separated IP addresses", text: $servers).font(.system(.body, design: .monospaced)) }
                            }.textFieldStyle(.roundedBorder)
                            Button("Save resolver") {
                                model.saveProvider(DNSProvider(name: providerName, endpoint: endpoint, servers: servers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }))
                            }
                            Text("An enabled resolver would receive your DNS queries. Encrypted DNS doesn’t hide your public IP or replace a VPN.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(.top, 14)
                    }.font(.system(size: 12))
                }
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Custom domain rules").font(.system(size: 14, weight: .semibold))
                            Text("Local testing only. Profiles start with no rules.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Profile", selection: $model.selectedID) { ForEach(model.profiles) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 145)
                    }
                    DisclosureGroup("Edit this profile") {
                        VStack(alignment: .leading, spacing: 16) {
                            TextField("Profile name", text: $profileName).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                            HStack(alignment: .top, spacing: 18) {
                                ruleEditor("Always allow", text: $allow)
                                ruleEditor("Block", text: $block)
                            }
                            Text("One domain per line, or paste a hosts-format list. A domain includes its subdomains. Always allow rules take priority.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            HStack {
                                Button("Save profile") { model.saveProfile(name: profileName, allow: allow, block: block); result = nil }
                                Button("Restore empty defaults") { model.restoreDefaults(); fillProfile(); result = nil }
                            }
                        }.padding(.top, 14)
                    }.font(.system(size: 12))
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try a domain").font(.system(size: 14, weight: .semibold))
                    Text("See how the saved profile would handle it. No network request is made.").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        TextField("example.com", text: $testDomain).textFieldStyle(.roundedBorder).frame(maxWidth: 360).onSubmit { evaluate() }
                        Button("Check rules") { evaluate() }.disabled(testDomain.isEmpty)
                    }.controlSize(.large)
                    if let result { Label(result, systemImage: "text.magnifyingglass").font(.system(size: 12)).textSelection(.enabled) }
                }
                if let message = model.message { InlineNotice(text: message) }
                Text("No VPN, privileged helper, or third-party blocklist is installed. System DNS logging and background protection are unavailable.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 950, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { fillProvider(model.provider); fillProfile() }
        .onChange(of: model.selectedID) { fillProfile(); result = nil }
    }
    private func ruleEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextEditor(text: text).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 140).background(Color.inspectorPanel, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.inspectorHairline)).accessibilityLabel(title)
        }.frame(maxWidth: .infinity)
    }
    private func fillProvider(_ provider: DNSProvider) { providerName = provider.name; endpoint = provider.endpoint; servers = provider.servers.joined(separator: ", ") }
    private func fillProfile() { let profile = model.selectedProfile; profileName = profile.name; allow = profile.allowlist; block = profile.blocklist }
    private func evaluate() {
        do {
            switch try model.selectedProfile.engine().evaluate(testDomain) {
            case .allowed(let rule): result = rule.map { "Would allow: matched \($0)" } ?? "Would allow: no matching block rule"
            case .blocked(let rule): result = "Would block: matched \(rule)"
            }
        } catch { result = error.localizedDescription }
    }
}
