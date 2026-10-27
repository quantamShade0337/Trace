import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            GeometryReader { sidebar in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 22, weight: .light)).foregroundStyle(Color.inspectorAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Network Inspector").font(.system(size: 13, weight: .semibold))
                            Text("ON THIS MAC").font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 26)
                    List(selection: $model.destination) {
                        Section {
                            ForEach(Array(Destination.allCases.prefix(5))) { destination in sidebarRow(destination) }
                        } header: { Text("Network").font(.system(size: 10, weight: .medium)) }
                        Section {
                            ForEach(Array(Destination.allCases.suffix(3))) { destination in sidebarRow(destination) }
                        } header: { Text("Workspace").font(.system(size: 10, weight: .medium)) }
                    }.listStyle(.sidebar)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(model.paused ? Color.secondary : Color.inspectorAccent).frame(width: 5, height: 5)
                            Text(model.paused ? "Monitoring paused" : "Monitoring this Mac").font(.system(size: 11))
                        }
                        Text("Your history stays here.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(18)
                }
                .frame(width: sidebar.size.width, height: sidebar.size.height)
            }
            .navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 240)
        } detail: {
            GeometryReader { detail in
                VStack(spacing: 0) {
                    Group {
                        switch model.destination ?? .overview {
                        case .overview: OverviewView(model: model)
                        case .connections: ConnectionsView(model: model)
                        case .processes: ProcessesView(model: model)
                        case .traceroute: TracerouteView(model: model.trace, geography: model.geography)
                        case .health: HealthView(model: model.health)
                        case .protection: ProtectionView(model: model.protection)
                        case .history: HistoryView(model: model)
                        case .settings: InspectorSettingsView(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(PageArrival(destination: model.destination))
                    Divider()
                    HStack(spacing: 6) {
                        Text(model.paused ? "Paused" : model.monitoringError == nil ? "Current-user network activity" : "Monitoring needs attention")
                        if let date = model.snapshotDate { Text("· Updated \(date.formatted(date: .omitted, time: .standard))").foregroundStyle(.secondary) }
                        Spacer()
                        Button { model.destination = .protection } label: { Label("DNS protection off", systemImage: "shield.slash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("View DNS protection availability")
                    }.font(.system(size: 10)).padding(.horizontal, 20).padding(.vertical, 9)
                }
                .frame(width: detail.size.width, height: detail.size.height)
            }
            .background(Color.inspectorBackground)
            .navigationTitle(model.destination?.rawValue ?? "Network Inspector")
            .toolbar {
                ToolbarItem {
                    Button(model.paused ? "Resume monitoring" : "Pause monitoring", systemImage: model.paused ? "play" : "pause") { model.togglePause() }
                        .help("Pause or resume monitoring (⌘⇧P)")
                }
            }
        }
        .background(WindowFrameGuard())
        .tint(.inspectorAccent)
        .frame(minWidth: 1000, minHeight: 700)
        .preferredColorScheme(model.preferences.colorScheme)
        .task { model.start() }
    }
    private func sidebarRow(_ destination: Destination) -> some View {
        HStack(spacing: 10) {
            Image(systemName: destination.symbol).font(.system(size: 13, weight: .regular)).frame(width: 18)
            Text(destination.rawValue).font(.system(size: 12))
        }.padding(.vertical, 5).tag(destination)
            .accessibilityElement(children: .ignore).accessibilityLabel(destination.rawValue)
    }
}

/// Animate only opacity after layout: native split views must never interpolate
/// their proposed size while switching between tables, maps and forms.
private struct PageArrival: ViewModifier {
    let destination: Destination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .task(id: destination) {
                guard !reduceMotion else { visible = true; return }
                visible = false
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) { visible = true }
            }
    }
}

/// Restored windows from a larger display must keep their controls on screen.
private struct WindowFrameGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> FrameView { FrameView() }
    func updateNSView(_ nsView: FrameView, context: Context) {}
    final class FrameView: NSView {
        private var checked = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !checked, let window else { return }
            checked = true
            Task { @MainActor [weak window] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let window, !window.styleMask.contains(.fullScreen), let screen = window.screen else { return }
                let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                var frame = window.frame
                frame.size.width = min(frame.width, available.width)
                frame.size.height = min(frame.height, available.height)
                frame.origin.x = max(available.minX, min(frame.minX, available.maxX - frame.width))
                frame.origin.y = max(available.minY, min(frame.minY, available.maxY - frame.height))
                if frame != window.frame { window.setFrame(frame, display: true) }
            }
        }
    }
}
