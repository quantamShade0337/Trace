import SwiftUI

struct HistoryView: View {
    let model: AppModel
    @State private var selection: UUID?
    @State private var search = ""
    @State private var kind = "All"
    @State private var confirmDelete = false
    @State private var exportError: String?
    private var rows: [HistoryEntry] { model.history.filter { (kind == "All" || $0.kind.rawValue == kind) && (search.isEmpty || $0.title.localizedStandardContains(search) || $0.detail.localizedStandardContains(search)) } }
    private var selected: HistoryEntry? { model.history.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "History", subtitle: "Revisit saved connections, routes, and network checks.")
                HStack {
                    TextField("Search history", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    Picker("Type", selection: $kind) { Text("All").tag("All"); ForEach(HistoryEntry.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.frame(width: 170)
                    Spacer()
                    Button("Delete all…", systemImage: "trash") { confirmDelete = true }.disabled(model.history.isEmpty)
                }
                if let error = model.storageError { StatusNote(text: error, warning: true) }
                if !model.preferences.recordHistory { StatusNote(text: "History recording is off. Existing records remain until deleted or expired.") }
            }.padding(24)
            Divider()
            HSplitView {
                List(rows, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.callout.weight(.medium)).lineLimit(2)
                        HStack { Text(entry.kind.rawValue); Spacer(); Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute().second()) }.font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 6).tag(entry.id)
                }.frame(minWidth: 260, idealWidth: 320)
                VStack(spacing: 0) {
                    if let selected {
                        HStack {
                            Text(selected.kind.rawValue).font(.headline)
                            Spacer()
                            Button("Copy", systemImage: "doc.on.doc") { Export.copy(selected.detail) }
                            Button("Export…", systemImage: "square.and.arrow.up") {
                                do { try Export.save(selected.detail, name: "network-observation.txt") } catch { exportError = error.localizedDescription }
                            }
                        }.padding(16)
                        Divider()
                        OutputView(text: selected.detail)
                    } else {
                        ContentUnavailableView(rows.isEmpty ? "No saved observations" : "Select an observation", systemImage: "clock.arrow.circlepath", description: Text(rows.isEmpty ? "Connections are saved every 30 seconds when recording is on. Traces and checks appear when they finish." : "Review the locally recorded evidence."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(minWidth: 300)
            }
            Text("Retained for \(model.preferences.retentionDays) days · up to 2,000 records / 32 MiB · socket observations are capped at 1,000 rows and 256 KiB each.")
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }
        .confirmationDialog("Delete all recorded network history?", isPresented: $confirmDelete) {
            Button("Delete all history", role: .destructive) { selection = nil; Task { await model.deleteHistory() } }
        } message: { Text("This removes saved observations, traces and diagnostics. New activity will continue to be recorded if enabled in Settings.") }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) { Button("OK") { exportError = nil } } message: { Text(exportError ?? "") }
    }
}
