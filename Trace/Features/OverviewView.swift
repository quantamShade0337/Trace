import SwiftUI
import Charts

struct OverviewView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Stable ordering prevents rows from jumping under the pointer as socket counts change.
    private var destinations: [RemoteDestination] {
        RemoteDestination.group(model.connections).sorted {
            let left = $0.processNames.first ?? "", right = $1.processNames.first ?? ""
            return left == right ? $0.host < $1.host : left.localizedStandardCompare(right) == .orderedAscending
        }
    }
    private var filtered: [RemoteDestination] {
        destinations.filter { search.isEmpty || "\($0.host) \($0.processNames.joined(separator: " ")) \(model.geography.location($0.host)?.place ?? "")".localizedStandardContains(search) }
    }
    private var selected: RemoteDestination? { destinations.first { $0.host == model.selectedMapHost } }
    private var pins: [GlobePin] {
        var values = destinations.compactMap { remote -> GlobePin? in
            guard let place = model.geography.location(remote.host) else { return nil }
            return GlobePin(id: remote.host, coordinate: place.coordinate, title: place.city.isEmpty ? place.country : place.city,
                            subtitle: "\(remote.host) · \(remote.count) connections · estimated location")
        }
        if let origin = model.geography.currentOrigin { values.append(GlobePin(id: "origin", coordinate: origin.coordinate, title: "Your internet exit", subtitle: origin.place + " · approximate public IP location", isOrigin: true)) }
        return values
    }
    private var arcs: [GlobeArc] {
        guard let origin = model.geography.currentOrigin else { return [] }
        return destinations.compactMap { remote in
            guard let location = model.geography.location(remote.host) else { return nil }
            return GlobeArc(id: remote.host, start: origin.coordinate, end: location.coordinate, selected: remote.host == model.selectedMapHost)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                PageHeading(title: "Your network", subtitle: "See where your apps connect.")
                LocationLookupButton(geography: model.geography, addresses: destinations.map(\.host))
                    .controlSize(.regular)
            }.padding(.horizontal, 24).padding(.vertical, 20)
            HStack(spacing: 24) {
                CompactStatistic(title: "Connections", value: String(model.connections.filter { $0.remote != nil }.count))
                CompactStatistic(title: "Apps & processes", value: String(model.processes.count))
                CompactStatistic(title: "Destinations", value: String(destinations.count))
                Spacer()
                Label(model.paused ? "Paused" : "Live observation", systemImage: model.paused ? "pause.circle" : "dot.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            GeometryReader { canvas in
            HStack(spacing: 0) {
                NetworkGlobeView(pins: pins, arcs: arcs, selection: $model.selectedMapHost)
                    .frame(minWidth: 350, maxWidth: .infinity).frame(height: canvas.size.height)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(selected == nil ? "Destinations" : "Connection details").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if selected != nil { Button("Back to destinations", systemImage: "xmark") { model.selectedMapHost = nil }.labelStyle(.iconOnly).buttonStyle(.plain) }
                    }.padding(16)
                    Divider()
                    Group {
                    if let selected { destinationDetail(selected).id(selected.host).transition(.opacity) }
                    else {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find an app or address", text: $search).textFieldStyle(.plain)
                        }.padding(12).background(Color.inspectorPanel)
                        Divider()
                        if filtered.isEmpty {
                            ContentUnavailableView(model.loading ? "Reading connections" : "No destinations", systemImage: "network", description: Text("Apps with an observed remote connection appear here."))
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(filtered) { destination in
                                        DestinationRow(destination: destination, location: model.geography.location(destination.host)) {
                                            model.selectedMapHost = destination.host
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selected?.host)
                    Spacer(minLength: 0)
                    Divider()
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle")
                        Text("Curves link estimated endpoints. Use Trace route to measure responding hops.")
                    }.font(.system(size: 10)).foregroundStyle(.secondary).padding(14)
                }
                .frame(width: 300).frame(height: canvas.size.height)
                .background(Color.inspectorPanel)
            }
            .frame(width: canvas.size.width, height: canvas.size.height)
            }.clipped()
            Divider()
            BandwidthChart(model: model).padding(.horizontal, 24).padding(.vertical, 16).fixedSize(horizontal: false, vertical: true)
            if let error = model.monitoringError { InlineNotice(text: error, warning: true).padding(.horizontal, 24).padding(.bottom, 10) }
            if let error = model.geography.error { InlineNotice(text: error, warning: true).padding(.horizontal, 24).padding(.bottom, 10) }
        }
    }

    private func destinationDetail(_ destination: RemoteDestination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let place = model.geography.location(destination.host) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(place.city.isEmpty ? place.country : place.city).font(.system(size: 22, weight: .semibold))
                        Text(place.country).font(.callout).foregroundStyle(.secondary)
                        Label("Estimated IP location", systemImage: "location.circle").font(.caption).foregroundStyle(.secondary)
                        Text("Located \(place.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if !place.organization.isEmpty { Text(place.organization).font(.callout) }
                } else {
                    Label(destination.isPublic ? "Location not looked up" : "Local or special-use address", systemImage: destination.isPublic ? "globe" : "network")
                        .font(.headline)
                    Text(destination.isPublic ? "Locate addresses to add this endpoint to the globe." : "Local and special-use addresses aren’t sent for geolocation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(destination.host).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Button("Trace route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    if let connection = destination.connections.first { model.investigate(connection) }
                }.buttonStyle(.borderedProminent).controlSize(.regular)
                Button("Inspect connections", systemImage: "list.bullet.rectangle") { model.showConnections(for: destination.host) }
                    .controlSize(.regular)
                Button("Copy IP address", systemImage: "doc.on.doc") { Export.copy(destination.host) }.controlSize(.regular)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(title: "CONNECTED APPS")
                    ForEach(destination.processNames, id: \.self) { name in
                        HStack(spacing: 9) {
                            ProcessIcon(pid: destination.connections.first { $0.process == name }?.pid ?? 0, size: 22)
                            Text(name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        }
                    }
                }
                LabeledContent("Observed connections", value: String(destination.count)).font(.caption)

            }.padding(18)
        }
    }
}

private struct DestinationRow: View {
    let destination: RemoteDestination
    let location: IPLocation?
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ProcessIcon(pid: destination.connections.first?.pid ?? 0, size: 27)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(location.map { $0.city.isEmpty ? $0.country : $0.city } ?? destination.processNames.first ?? "Unknown process")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(String(destination.count)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text(destination.host).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(location == nil ? (destination.isPublic ? "Not located" : "Local / special-use") : destination.processNames.joined(separator: ", "))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary).padding(.top, 4)
            }.padding(.horizontal, 16).padding(.vertical, 13).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(hovered ? Color.primary.opacity(0.035) : .clear)
        .onHover { hovered = $0 }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 53) }
        .accessibilityLabel("\(destination.host), \(destination.count) connections, \(location?.place ?? "location unknown")")
    }
}

struct BandwidthChart: View {
    let model: AppModel
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                SectionEyebrow(title: "NETWORK ACTIVITY")
                HStack(spacing: 18) {
                    rate("arrow.down", value: model.currentRate?.download)
                    rate("arrow.up", value: model.currentRate?.upload)
                }
                Text(model.bandwidth.last?.interfaces.joined(separator: ", ") ?? "Waiting for an interface")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: 245, alignment: .leading)
            if model.bandwidth.count < 2 {
                HStack { Image(systemName: "waveform.path"); Text(model.paused ? "Sampling paused" : "Measuring network activity…") }
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 65)
            } else {
                Chart(model.bandwidth) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("Bytes per second", sample.download), series: .value("Direction", "Download"))
                        .foregroundStyle(Color.inspectorAccent).lineStyle(StrokeStyle(lineWidth: 1.5))
                    LineMark(x: .value("Time", sample.date), y: .value("Bytes per second", sample.upload), series: .value("Direction", "Upload"))
                        .foregroundStyle(Color.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().font(.system(size: 9)) } }
                .chartYAxis(.hidden).chartLegend(.hidden).frame(height: 65)
                .accessibilityLabel("Measured download and upload rates over the last 120 samples")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let error = model.bandwidthError { Text(error).font(.caption2).foregroundStyle(.orange) }
        }
    }
    private func rate(_ symbol: String, value: Double?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(symbol == "arrow.down" ? Color.inspectorAccent : .secondary)
            Text(rateString(value)).font(.system(size: 15, weight: .medium)).monospacedDigit().contentTransition(.numericText())
        }
    }
}
