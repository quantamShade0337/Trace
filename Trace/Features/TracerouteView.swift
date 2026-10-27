import SwiftUI

struct TracerouteView: View {
    @Bindable var model: TraceModel
    @Bindable var geography: GeographyModel
    @State private var mode = "Globe"
    @State private var options = false
    @State private var exportError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: TraceHop? { model.hops.first { $0.number == model.selectedHop } }
    private var responded: Int { model.hops.filter { $0.address != nil }.count }
    private var selection: Binding<String?> {
        Binding(get: { model.selectedHop.map(String.init) }, set: { model.selectedHop = $0.flatMap(Int.init) })
    }
    private var pins: [GlobePin] {
        model.hops.compactMap { hop in
            guard let address = hop.address, let location = geography.location(address) else { return nil }
            return GlobePin(id: String(hop.number), coordinate: location.coordinate,
                            title: "\(hop.number) · \(location.city.isEmpty ? location.country : location.city)",
                            subtitle: "\(address) · approximate IP location")
        }
    }
    private var arcs: [GlobeArc] {
        GeographicSegment.trace(hops: model.hops, locations: geography.locations.filter { geography.location($0.key) != nil }).enumerated().map { index, segment in
            GlobeArc(id: "\(index):\(segment.from):\(segment.to)", start: segment.start, end: segment.end, selected: selected?.address == segment.to)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PageHeading(title: "Trace a route", subtitle: "Follow the network hops between this Mac and a destination.")
                    Picker("View", selection: $mode) { Text("Globe").tag("Globe"); Text("Text output").tag("Text") }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Enter a domain or IP address", text: $model.destination)
                            .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).onSubmit { model.run() }
                            .disabled(model.isRunning)
                    }.padding(10).background(Color.inspectorPanel, in: .rect(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.inspectorHairline.opacity(0.7)))
                    Button("Trace options", systemImage: "slider.horizontal.3") { options.toggle() }.labelStyle(.iconOnly).controlSize(.large)
                        .popover(isPresented: $options) { traceOptions }
                    if model.isRunning {
                        Button("Stop trace", systemImage: "stop.fill") { model.cancel() }.controlSize(.large)
                    } else {
                        Button("Trace route", systemImage: "arrow.right") { model.run() }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.destination.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let error = model.error { InlineNotice(text: error, warning: true) }
                HStack(spacing: 14) {
                    if model.isRunning { ProgressView().controlSize(.mini) }
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !model.hops.isEmpty {
                        Text("\(responded) responded · \(model.hops.count - responded) no reply").font(.system(size: 11)).foregroundStyle(.secondary)
                        LocationLookupButton(geography: geography, addresses: model.hops.compactMap(\.address)).controlSize(.small)
                    }
                    Menu {
                        Button("Copy trace output", systemImage: "doc.on.doc") { Export.copy(model.output) }
                        Button("Export trace…", systemImage: "square.and.arrow.up") {
                            do { try Export.save(model.output, name: "traceroute.txt") } catch { exportError = error.localizedDescription }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 18) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.output.isEmpty).help("Copy or export trace output")
                }
            }.padding(24)
            Divider()
            GeometryReader { canvas in
            ZStack {
                HStack(spacing: 0) {
                    NetworkGlobeView(pins: pins, arcs: arcs, selection: selection,
                                     emptyTitle: model.hops.isEmpty ? "See the journey, hop by hop." : "Add geography to your trace.",
                                     emptyDescription: model.hops.isEmpty ? "Start a trace to discover responding routers. Then locate public hops on the globe." : "Choose Locate addresses to map public hops. Local routers and unanswered hops stay in the route list.")
                        .frame(minWidth: 350, maxWidth: .infinity).frame(height: canvas.size.height)
                    Divider()
                    routeInspector.frame(width: 300).frame(height: canvas.size.height).background(Color.inspectorPanel)
                }.frame(width: canvas.size.width, height: canvas.size.height)
                    .opacity(mode == "Globe" ? 1 : 0).allowsHitTesting(mode == "Globe").accessibilityHidden(mode != "Globe")
                if mode == "Text" { OutputView(text: model.output).background(Color.inspectorBackground).transition(.opacity) }
            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: mode)
            }.clipped()
            Divider()
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                Text("Locations are estimates. Curves join consecutive located hops; gaps stay unknown. Diagnostic probes can follow a different path than an app’s traffic.")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            if let error = geography.error { InlineNotice(text: error, warning: true).padding(.horizontal, 20).padding(.bottom, 10) }
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var routeInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Route timeline").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.hops.isEmpty ? "" : "\(model.hops.count) hops · ms").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(16)
            Divider()
            if model.hops.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    step("1", title: "Choose a destination", detail: "Enter a domain, IP, or pick Trace from a connection.")
                    step("2", title: "Discover the hops", detail: "See which routers answer and how long each probe takes.")
                    step("3", title: "Explore the geography", detail: "Optionally locate public hops. Private addresses stay local.")
                }.padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.hops) { hop in
                            Button { model.selectedHop = hop.number } label: {
                                HStack(alignment: .top, spacing: 11) {
                                    Text(String(format: "%02d", hop.number)).font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(model.selectedHop == hop.number ? Color.inspectorAccent : .secondary)
                                        .frame(width: 25, height: 25)
                                        .background(Color.inspectorPanel, in: .circle)
                                        .overlay(Circle().strokeBorder(model.selectedHop == hop.number ? Color.inspectorAccent : Color.inspectorHairline, lineWidth: 1))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(hop.address ?? "No reply").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                        Text(hop.address.flatMap(geography.location)?.place ?? (hop.address == nil ? "The router did not answer" : IPAddress(hop.address ?? "")?.isPublic == true ? "Not located" : "Local / special-use"))
                                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text(hop.average.map { String(format: "%.1f", $0) } ?? "*").font(.system(size: 11, weight: .medium, design: .monospaced))
                                }.padding(.horizontal, 16).padding(.vertical, 13)
                                    .background(alignment: .leading) {
                                        Rectangle().fill(Color.inspectorHairline).frame(width: 1)
                                            .padding(.top, hop.id == model.hops.first?.id ? 25 : 0)
                                            .padding(.bottom, hop.id == model.hops.last?.id ? 25 : 0)
                                            .padding(.leading, 28)
                                    }
                                    .background(model.selectedHop == hop.number ? Color.inspectorAccent.opacity(0.09) : .clear)
                                    .contentShape(.rect)
                            }.buttonStyle(.plain)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                                .accessibilityLabel("Hop \(hop.number), \(hop.label), \(hop.average.map { String(format: "%.1f milliseconds", $0) } ?? "no reply")")
                        }
                    }.animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.hops.count)
                }
            }
            Spacer(minLength: 0)
            if let selected {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(title: "HOP \(selected.number)")
                    HStack(alignment: .firstTextBaseline) {
                        Text(selected.average.map { String(format: "%.2f", $0) } ?? "—").font(.system(size: 25, weight: .medium)).monospacedDigit()
                        Text("ms round trip").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(selected.hostname ?? selected.address ?? "This hop did not respond.").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    if let annotation = selected.annotation { Text("Probe response: \(annotation)").font(.caption).foregroundStyle(.secondary) }
                    Text("One diagnostic probe. This measures response time, not the router’s physical distance.").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(18)
            }
        }
    }
    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number).font(.system(size: 10, weight: .medium)).frame(width: 23, height: 23).background(.quaternary, in: .circle)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var traceOptions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Trace options").font(.headline)
            Stepper("Maximum hops: \(model.maxHops)", value: $model.maxHops, in: 1...64)
            Picker("Wait per hop", selection: $model.wait) { ForEach(1...5, id: \.self) { Text("\($0) seconds").tag($0) } }
            Toggle("Resolve router names", isOn: $model.resolveNames).toggleStyle(.checkbox)
            Text("One probe per hop limits diagnostic traffic. Name resolution may add time.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 300).disabled(model.isRunning)
    }
}
