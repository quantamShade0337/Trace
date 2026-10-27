import SwiftUI

struct InspectorSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Picker("Appearance", selection: $preferences.appearance) { Text("Dark").tag("Dark"); Text("Light").tag("Light"); Text("System").tag("System") }
                Picker("Refresh connections", selection: $preferences.pollInterval) { ForEach([2, 3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) } }
                Picker("Bandwidth interface", selection: $preferences.selectedInterface) {
                    Text("Automatic (Wi-Fi & Ethernet)").tag("automatic")
                    ForEach(model.interfaces) { interface in Text("\(interface.name)\(interface.isUp ? "" : " · down")").tag(interface.name) }
                    if preferences.selectedInterface != "automatic", !model.interfaces.contains(where: { $0.name == preferences.selectedInterface }) {
                        Text("\(preferences.selectedInterface) · unavailable").tag(preferences.selectedInterface)
                    }
                }
                Text("Automatic uses active Wi-Fi and Ethernet interfaces, without counting tunnel traffic twice. Rates include all apps and network overhead.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Monitoring") }
            Section {
                Toggle("Record local history", isOn: $preferences.recordHistory)
                Picker("Retention", selection: $preferences.retentionDays) { ForEach([1, 7, 30], id: \.self) { Text("\($0) \($0 == 1 ? "day" : "days")").tag($0) } }
                LabeledContent("Storage limit", value: "2,000 records / 32 MiB · 256 KiB per record")
                LabeledContent("Location") { Text(model.store.url.path).font(.caption).textSelection(.enabled) }
                Text("Network metadata can be sensitive. History contains process names, endpoints and diagnostic output. It is never uploaded. Exports are created only when you choose a destination.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Review or delete history", systemImage: "clock.arrow.circlepath") { model.destination = .history }
            } header: { Text("Privacy & storage") }
            Section {
                LabeledContent("Location provider", value: "IPWHOIS.io (ipwho.is)")
                LabeledContent("Lookup mode", value: "Only when you request it")
                LabeledContent("Located addresses", value: String(model.geography.locations.count))
                Text("Apple Maps loads map imagery from Apple. Choosing Locate addresses sends only the displayed public IPs to ipwho.is, which also estimates your public internet exit location. No GPS, app names, ports or history are shared. Results are approximate and kept in memory only.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear saved map locations", systemImage: "location.slash") { model.geography.clear() }
                    .disabled(model.geography.running || (model.geography.locations.isEmpty && model.geography.origin == nil))
            } header: { Text("Connection map") }
            Section {
                LabeledContent("Socket visibility", value: "Current user · best effort")
                LabeledContent("System DNS protection", value: "Unavailable in this build")
                LabeledContent("Background protection", value: "Unavailable")
                Text("This directly distributed inspector uses system diagnostic utilities outside App Sandbox. It does not request root access, install helpers, change DNS, inspect TLS content, or modify firewall rules. Closing the last window or quitting cancels diagnostics and exits the app.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("No accounts, telemetry, subscriptions, or developer-operated services. No open-source license has been chosen.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Capabilities") }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: preferences.selectedInterface) { model.changeInterface() }
        .onChange(of: preferences.retentionDays) { Task { await model.refreshHistory() } }
    }
}
