import SwiftUI
import AppKit

@main
struct NetworkInspectorApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    var body: some Scene {
        Window("Network Inspector", id: "inspector") {
            ContentView(model: model)
                .task { delegate.model = model }
                .onDisappear { model.stop() }
        }
        .defaultSize(width: 1200, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(model.paused ? "Resume Monitoring" : "Pause Monitoring") { model.togglePause() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Connections") { model.destination = .connections }.keyboardShortcut("2", modifiers: .command)
                Button("Traceroute") { model.destination = .traceroute }.keyboardShortcut("4", modifiers: .command)
                Button("Overview") { model.destination = .overview }.keyboardShortcut("1", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.destination = .settings }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
