import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Color {
    static let inspectorAccent = Color("AccentColor")
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 22, weight: .semibold)).tracking(-0.4)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusNote: View {
    let text: String
    var warning = false
    var body: some View {
        Label(text, systemImage: warning ? "exclamationmark.triangle" : "info.circle")
            .font(.callout).foregroundStyle(warning ? Color.orange : .secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }
}

struct Metric: View {
    let title: String
    let value: String
    var symbol: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).foregroundStyle(Color.inspectorAccent) }
                Text(title).foregroundStyle(.secondary)
            }.font(.callout)
            Text(value).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func rateString(_ bytes: Double?) -> String {
    guard let bytes else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .decimal) + "/s"
}

@MainActor
enum Export {
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    static func save(_ text: String, name: String) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct OutputView: View {
    let text: String
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text.isEmpty ? "No output yet." : text)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct SectionEyebrow: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary) }
}

struct CompactStatistic: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value).font(.system(size: 19, weight: .medium)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct InlineNotice: View {
    let text: String
    var warning = false
    var body: some View {
        Label(text, systemImage: warning ? "exclamationmark.triangle" : "info.circle")
            .font(.system(size: 11)).foregroundStyle(warning ? Color.orange : .secondary)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private enum ProcessIconCache {
    static var values: [Int: (date: Date, icon: NSImage)] = [:]
    static func icon(for pid: Int) -> NSImage? {
        if let cached = values[pid], Date.now.timeIntervalSince(cached.date) < 60 { return cached.icon }
        guard let application = NSRunningApplication(processIdentifier: pid_t(pid)), let icon = application.icon else { return nil }
        if values.count >= 256 { values.removeAll(keepingCapacity: true) }
        values[pid] = (.now, icon)
        return icon
    }
}

struct ProcessIcon: View {
    let pid: Int
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let icon = ProcessIconCache.icon(for: pid) { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: "app").resizable().scaledToFit().foregroundStyle(.secondary).padding(3) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

func connectionStateLabel(_ state: String) -> String {
    switch state {
    case "ESTABLISHED": "Connected"
    case "LISTEN": "Waiting for connections"
    case "DATAGRAM": "UDP socket"
    case "CLOSE_WAIT", "FIN_WAIT_1", "FIN_WAIT_2", "LAST_ACK", "CLOSING": "Closing"
    case "CLOSED": "Closed"
    case "SYN_SENT", "SYN_RECEIVED": "Connecting"
    default: state.capitalized.replacingOccurrences(of: "_", with: " ")
    }
}
