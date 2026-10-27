import SwiftUI
import AppKit

struct ConnectionsView: View {
    @Bindable var model: AppModel
    @State private var scope = ConnectionScope.all
    @State private var selection: Connection.ID?
    @State private var sortOrder = [KeyPathComparator(\Connection.process)]
    private var rows: [Connection] { model.connections.filter(ConnectionQuery(text: model.connectionSearch, scope: scope).matches).sorted(using: sortOrder) }
    private var selected: Connection? { model.connections.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Connections", subtitle: "Find an app, inspect its connections, or trace a destination.")
                HStack {
                    TextField("Search app, IP address or process", text: $model.connectionSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    if !model.connectionSearch.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { model.connectionSearch = "" }.labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary) }
                    Spacer()
                    Picker("Filter", selection: $scope) { ForEach(ConnectionScope.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 175)
                    Text("\(rows.count) connections").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let error = model.monitoringError { StatusNote(text: "Last snapshot retained. \(error)", warning: true) }
            }.padding(24)
            Divider()
            HSplitView {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Process", value: \.process) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                ProcessIcon(pid: row.pid, size: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.process).font(.system(size: 12, weight: .medium))
                                    Text("PID \(String(row.pid))").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 4)
                    }.width(min: 110, ideal: 150)
                    TableColumn("Protocol", value: \.transport).width(65)
                    TableColumn("Remote endpoint", value: \.remoteDisplay) { row in Text(row.remoteDisplay).font(.system(.caption, design: .monospaced)) }.width(min: 130, ideal: 210)
                    TableColumn("State", value: \.state) { row in
                        Text(connectionStateLabel(row.state)).font(.system(size: 11)).foregroundStyle(row.state == "ESTABLISHED" ? Color.inspectorAccent : .secondary)
                    }.width(min: 100, ideal: 145)
                }
                .contextMenu(forSelectionType: Connection.ID.self) { ids in
                    if let row = model.connections.first(where: { ids.contains($0.id) }) {
                        Button("Copy endpoints") { Export.copy("\(row.local.display) → \(row.remoteDisplay)") }
                        Button("Trace destination") { model.investigate(row) }.disabled(!row.isTraceable)
                    }
                }
                .overlay { if rows.isEmpty { ContentUnavailableView.search(text: model.connectionSearch) } }
                if let selected {
                    ConnectionInspector(connection: selected, location: selected.remote.flatMap { model.geography.location($0.host) },
                                        investigate: { model.investigate(selected) },
                                        showOnMap: {
                                            model.selectedMapHost = selected.remote.flatMap { IPAddress($0.host)?.canonical ?? $0.host }
                                            model.destination = .overview
                                        }, close: { selection = nil })
                        .frame(minWidth: 235, idealWidth: 270, maxWidth: 320)
                }
            }
            Text("Current observation only. Visibility depends on macOS permissions; short-lived sockets may be missed.")
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}

struct ConnectionInspector: View {
    let connection: Connection
    let location: IPLocation?
    let investigate: () -> Void
    let showOnMap: () -> Void
    let close: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Connection details").font(.headline)
                    Spacer()
                    Button("Close inspector", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProcessIcon(pid: connection.pid, size: 40).padding(.bottom, 4)
                    Text(connection.process).font(.title2.weight(.semibold))
                    Text("Process \(String(connection.pid)) · descriptor \(connection.descriptor)").font(.caption).foregroundStyle(.secondary)
                    if let application = NSRunningApplication(processIdentifier: pid_t(connection.pid)), let url = application.executableURL {
                        Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Divider()
                detail("Local endpoint", connection.local.display)
                detail("Remote endpoint", connection.remoteDisplay)
                detail("Status", connectionStateLabel(connection.state))
                if let location { detail("Estimated location", location.place) }
                detail("Observed", connection.observedAt.formatted(date: .abbreviated, time: .standard))
                Button("Trace destination", systemImage: "point.topleft.down.to.point.bottomright.curvepath", action: investigate)
                    .buttonStyle(.borderedProminent).disabled(!connection.isTraceable)
                Button("Show on globe", systemImage: "globe", action: showOnMap).disabled(connection.remote == nil)
                Button("Copy details", systemImage: "doc.on.doc") { Export.copy("\(connection.process) (\(connection.pid))\n\(connection.local.display) → \(connection.remoteDisplay)\n\(connection.transport) \(connection.state)") }
                DisclosureGroup("Technical details") {
                    VStack(alignment: .leading, spacing: 12) {
                        detail("Transport", connection.transport)
                        detail("Socket state", connection.state)
                        detail("File descriptor", connection.descriptor)
                        Text("An IP address doesn’t establish which domain is being accessed or whether a connection is safe.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                }.font(.caption)
            }.padding(20)
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }
    }
}

struct ProcessesView: View {
    let model: AppModel
    @State private var search = ""
    @State private var selectedPID: Int?
    @State private var sortOrder = [KeyPathComparator(\ProcessSummary.count, order: .reverse)]
    private var rows: [ProcessSummary] { model.processes.filter { search.isEmpty || "\($0.name) \($0.pid)".localizedStandardContains(search) }.sorted(using: sortOrder) }
    private var selected: ProcessSummary? { model.processes.first { $0.pid == selectedPID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Processes", subtitle: "See which apps and background processes are using the network.")
                TextField("Find a process or PID", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                if let error = model.monitoringError { StatusNote(text: "Last snapshot retained. \(error)", warning: true) }
            }.padding(24)
            HSplitView {
                Table(rows, selection: $selectedPID, sortOrder: $sortOrder) {
                    TableColumn("Process", value: \.name) { row in
                        HStack(spacing: 9) { ProcessIcon(pid: row.pid, size: 22); Text(row.name).font(.system(size: 12, weight: .medium)) }.padding(.vertical, 5)
                    }
                    TableColumn("PID", value: \.pid) { Text(String($0.pid)).font(.system(size: 11, design: .monospaced)) }.width(80)
                    TableColumn("Sockets", value: \.count) { Text("\($0.count)").monospacedDigit() }.width(80)
                }
                VStack(alignment: .leading, spacing: 16) {
                    if let selected {
                        Text(selected.name).font(.title2.weight(.semibold))
                        Text("PID \(String(selected.pid)) · \(selected.count) connections").font(.callout).foregroundStyle(.secondary)
                        Divider()
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(selected.connections) { connection in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(connection.remoteDisplay == "—" ? connection.local.display : connection.remoteDisplay).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                        HStack {
                                            Text("\(connection.transport) · \(connectionStateLabel(connection.state))").font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            if connection.isTraceable { Button("Trace") { model.investigate(connection) }.font(.caption) }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("Select a process", systemImage: "square.stack.3d.up", description: Text("Inspect its observed endpoints and trace a remote destination."))
                    }
                }.padding(24).frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Text("Only processes with visible network sockets appear. Per-process throughput is unavailable.")
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
