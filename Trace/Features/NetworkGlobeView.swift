import SwiftUI
import MapKit

extension GeoCoordinate {
    var mapCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct GlobePin: Identifiable, Equatable {
    let id: String
    let coordinate: GeoCoordinate
    let title: String
    let subtitle: String
    var isOrigin = false
}

private struct GlobePinGroup: Identifiable {
    let coordinate: GeoCoordinate
    let pins: [GlobePin]
    var id: String { "\(coordinate.latitude):\(coordinate.longitude)" }
}

struct GlobeArc: Identifiable, Equatable {
    let id: String
    let start: GeoCoordinate
    let end: GeoCoordinate
    var selected = false
    var coordinates: [CLLocationCoordinate2D] { [start.mapCoordinate, end.mapCoordinate] }
}

/// All positions are returned by a disclosed IP lookup. The camera's initial view is just a world view.
struct NetworkGlobeView: View {
    let pins: [GlobePin]
    let arcs: [GlobeArc]
    @Binding var selection: String?
    var emptyTitle = "Your connections, around the world."
    var emptyDescription = "Locate public addresses to see their approximate destinations."
    var showEmptyExplanation = true
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: .init(latitude: 15, longitude: 15), span: .init(latitudeDelta: 180, longitudeDelta: 360)))
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinGroups: [GlobePinGroup] {
        Dictionary(grouping: pins, by: \.coordinate)
            .map { GlobePinGroup(coordinate: $0.key, pins: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.id < $1.id }
    }
    var body: some View {
        Map(position: $camera, bounds: MapCameraBounds(minimumDistance: 1_000, maximumDistance: 150_000_000), interactionModes: [.pan, .zoom, .rotate]) {
            ForEach(arcs) { arc in
                MapPolyline(coordinates: arc.coordinates, contourStyle: .geodesic)
                    .stroke(arc.selected ? Color.inspectorAccent : Color.inspectorAccent.opacity(0.5), style: StrokeStyle(lineWidth: arc.selected ? 2.5 : 1.25, lineCap: .round))
            }
            ForEach(pinGroups) { group in
                let pin = group.pins.first(where: { $0.id == selection }) ?? group.pins.first(where: \.isOrigin) ?? group.pins[0]
                Annotation(pin.title, coordinate: pin.coordinate.mapCoordinate, anchor: .center) {
                    Button {
                        if let index = group.pins.firstIndex(where: { $0.id == selection }) {
                            selection = group.pins[(index + 1) % group.pins.count].id
                        } else { selection = pin.id }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: pin.isOrigin ? "desktopcomputer" : "circle.fill")
                                .font(.system(size: pin.isOrigin ? 13 : 6, weight: .semibold))
                            if group.pins.count > 1 { Text(String(group.pins.count)).font(.system(size: 10, weight: .semibold)).monospacedDigit() }
                            if selection == pin.id || pin.isOrigin { Text(pin.title).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                        }
                        .padding(.horizontal, selection == pin.id || pin.isOrigin ? 10 : 6).frame(height: 28)
                        .foregroundStyle(pin.isOrigin ? Color.primary : Color.inspectorAccent)
                        .background(Color.inspectorPanel, in: .capsule)
                        .overlay(Capsule().strokeBorder(selection == pin.id ? Color.inspectorAccent : Color.inspectorHairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(group.pins.count > 1 ? "\(group.pins.count) addresses share this estimated location. Click to cycle; use the list to inspect each." : pin.subtitle)
                    .accessibilityLabel("\(pin.title). \(pin.subtitle)\(group.pins.count > 1 ? ". \(group.pins.count) addresses at this location; click to cycle." : "")")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GLOBAL VIEW").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Text(pins.filter { !$0.isOrigin }.isEmpty ? "Addresses not yet located" : "\(pins.filter { !$0.isOrigin }.count) located \(pins.filter { !$0.isOrigin }.count == 1 ? "address" : "addresses")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12).background(Color.inspectorPanel, in: .rect(cornerRadius: 8)).padding(18)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 0) {
                mapButton("View whole globe", symbol: "globe") { reset() }
                Divider().frame(width: 20)
                mapButton("Focus selected destination", symbol: "scope") { focus() }.disabled(!pins.contains { $0.id == selection })
            }
            .padding(4).background(Color.inspectorPanel, in: .rect(cornerRadius: 8)).padding(18)
        }
        .overlay(alignment: .bottomTrailing) {
            if showEmptyExplanation && pins.filter({ !$0.isOrigin }).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(emptyTitle).font(.system(size: 15, weight: .semibold))
                    Text(emptyDescription).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 270, alignment: .leading).padding(16)
                .background(Color.inspectorPanel, in: .rect(cornerRadius: 10)).padding(.trailing, 18).padding(.bottom, 42)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !pins.filter({ !$0.isOrigin }).isEmpty, let url = URL(string: "https://ipwhois.io") {
                Link("IP locations: IPWHOIS.io · approximate", destination: url)
                    .font(.system(size: 9)).foregroundStyle(.secondary).padding(8)
                    .background(Color.inspectorPanel, in: .rect(cornerRadius: 6)).padding(.trailing, 12).padding(.bottom, 12)
            }
        }
        .task {
            // Navigation creates a new map; restore its existing selection immediately.
            if selection != nil { focus() } else { reset() }
        }
        .onChange(of: selection) { focus() }
        .onChange(of: pins.map(\.id)) { old, new in
            if let selection, !old.contains(selection), new.contains(selection) { focus() }
            else if !old.contains("origin"), new.contains("origin"), selection == nil { reset() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interactive Apple Maps globe. Locations are IP estimates. Use the destination list for a text alternative.")
    }
    private func mapButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action).labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 30, height: 30).help(title)
    }
    private func reset() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) {
            camera = .region(MKCoordinateRegion(center: pins.first(where: \.isOrigin)?.coordinate.mapCoordinate ?? pins.first?.coordinate.mapCoordinate ?? .init(latitude: 15, longitude: 15), span: .init(latitudeDelta: 180, longitudeDelta: 360)))
        }
    }
    private func focus() {
        guard let pin = pins.first(where: { $0.id == selection }) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) {
            camera = .camera(MapCamera(centerCoordinate: pin.coordinate.mapCoordinate, distance: 12_000_000))
        }
    }
}

struct LocationLookupButton: View {
    @Bindable var geography: GeographyModel
    let addresses: [String]
    private struct LookupBatch: Identifiable {
        let id = UUID()
        let addresses: [String]
    }
    @State private var batch: LookupBatch?
    var body: some View {
        if geography.running {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Locating \(geography.completed)/\(geography.total)").font(.caption).monospacedDigit()
                Button("Stop") { geography.cancel() }.font(.caption)
            }
        } else {
            Button("Locate addresses", systemImage: "location.magnifyingglass") {
                batch = LookupBatch(addresses: geography.pending(addresses))
            }
            .disabled(!addresses.contains { IPAddress($0)?.isPublic == true } || (geography.pending(addresses).isEmpty && geography.currentOrigin != nil))
            .popover(item: $batch, arrowEdge: .bottom) { request in
                let disclosed = request.addresses
                VStack(alignment: .leading, spacing: 16) {
                    Label("Add approximate locations", systemImage: "globe").font(.headline)
                    Text("Send the \(disclosed.count) public IP \(disclosed.count == 1 ? "address" : "addresses") below to ipwho.is. The provider also estimates your public internet exit location. No app names, ports or history are sent.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    if !disclosed.isEmpty {
                        ScrollView {
                            Text(disclosed.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 125)
                    }
                    Text("These are estimates, not device locations. Anycast and VPNs can make them misleading. Up to 64 addresses per request; results stay in memory for up to 24 hours.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if let policy = URL(string: "https://ipwhois.io/privacy-policy") { Link("Privacy policy", destination: policy) }
                        Spacer()
                        Button("Cancel") { batch = nil }
                        Button("Locate these addresses") { geography.locate(disclosed); batch = nil }.buttonStyle(.borderedProminent)
                    }
                }.padding(20).frame(width: 370)
            }
        }
    }
}
