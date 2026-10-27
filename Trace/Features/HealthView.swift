import SwiftUI

struct HealthView: View {
    @Bindable var model: HealthModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Network health", subtitle: "Find out why a connection feels slow or unavailable.")
                HStack(spacing: 12) {
                    TextField("Domain or IP address to check", text: $model.destination).textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 380).onSubmit { model.run() }.disabled(model.running)
                    if model.running {
                        ProgressView().controlSize(.small)
                        Button("Stop") { model.cancel() }
                    } else {
                        Button("Check connection", systemImage: "stethoscope") { model.run() }.buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if let report = model.report { Button("Copy report", systemImage: "doc.on.doc") { Export.copy(report.text) } }
                }.controlSize(.large)
                DisclosureGroup("What happens when I run a check?") {
                    Text("Sends an HTTPS HEAD request and four ICMP probes to your destination, looks up its address using the system resolver, and reads your current route and DNS settings. HTTPS redirects may be followed. DNS answers may be cached.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                if let error = model.error { InlineNotice(text: error, warning: true) }
                if let report = model.report {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(report.checks.allSatisfy(\.succeeded) ? "All checks returned a result" : "Some checks need a closer look")
                                .font(.system(size: 17, weight: .semibold))
                            Text("\(report.destination) · \(report.date.formatted(date: .omitted, time: .standard))").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(report.checks.filter(\.succeeded).count) of \(report.checks.count) available").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(report.checks) { check in
                            DisclosureGroup {
                                Text(check.detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: symbol(check.id)).font(.system(size: 17, weight: .light)).foregroundStyle(.secondary).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(title(check.id)).font(.system(size: 13, weight: .medium))
                                        Text(explanation(check.id)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 20)
                                    Text(check.value).font(.system(size: 12, weight: .medium)).monospacedDigit()
                                    Image(systemName: check.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                                        .font(.system(size: 13)).foregroundStyle(check.succeeded ? Color.inspectorAccent : .orange)
                                }.padding(.vertical, 19)
                            }
                            Divider()
                        }
                    }
                    Text("One destination doesn’t describe the entire internet. Blocked probes or a server’s TLS settings can cause individual checks to fail.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        Text(model.running ? "Checking your connection…" : "A clearer answer than “it’s slow”.")
                            .font(.system(size: 18, weight: .medium)).padding(.top, 14)
                        Text("Check secure connectivity, name resolution, response times, and the route your Mac is using. Expand any result to see the evidence.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: 480, alignment: .leading)
                    }
                }
            }.padding(28).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func symbol(_ id: String) -> String {
        switch id { case "https": "lock"; case "resolve": "text.magnifyingglass"; case "ping": "waveform.path"; case "route": "arrow.triangle.branch"; default: "server.rack" }
    }
    private func title(_ id: String) -> String {
        switch id { case "https": "Secure connection"; case "resolve": "Address lookup"; case "ping": "Response time & packet loss"; case "route": "Gateway & interface"; default: "DNS configuration" }
    }
    private func explanation(_ id: String) -> String {
        switch id {
        case "https": "Can your Mac reach the destination over HTTPS?"
        case "resolve": "How quickly can macOS find the destination’s IP?"
        case "ping": "Do diagnostic probes return, and how quickly?"
        case "route": "Which local gateway does your Mac use?"
        default: "Which resolvers are currently configured?"
        }
    }
}
