import SwiftUI
import Observation

@MainActor @Observable
final class Preferences {
    var pollInterval: Int { didSet { defaults.set(pollInterval, forKey: "pollInterval") } }
    var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays") } }
    var recordHistory: Bool { didSet { defaults.set(recordHistory, forKey: "recordHistory") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var selectedInterface: String { didSet { defaults.set(selectedInterface, forKey: "selectedInterface") } }
    private let defaults: UserDefaults
    var colorScheme: ColorScheme? { appearance == "System" ? nil : appearance == "Dark" ? .dark : .light }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let interval = defaults.integer(forKey: "pollInterval")
        pollInterval = [2, 3, 5, 10].contains(interval) ? interval : 3
        let retention = defaults.integer(forKey: "retentionDays")
        retentionDays = [1, 7, 30].contains(retention) ? retention : 7
        recordHistory = defaults.object(forKey: "recordHistory") as? Bool ?? true
        appearance = defaults.string(forKey: "appearance") ?? "Dark"
        selectedInterface = defaults.string(forKey: "selectedInterface") ?? "automatic"
    }
}

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", connections = "Connections", processes = "Processes", traceroute = "Traceroute"
    case health = "Network Health", protection = "Protection", history = "History", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .processes: "square.stack.3d.up"
        case .traceroute: "point.topleft.down.to.point.bottomright.curvepath"
        case .health: "heart.text.clipboard"
        case .protection: "shield.lefthalf.filled"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

@MainActor @Observable
final class AppModel {
    let preferences = Preferences()
    let geography = GeographyModel()
    var selectedMapHost: String?
    var connectionSearch = ""
    let trace = TraceModel()
    let health = HealthModel()
    let protection = ProtectionModel()
    var destination: Destination? = .overview
    var connections: [Connection] = []
    var bandwidth: [BandwidthSample] = []
    private var latestRate: BandwidthSample?
    var interfaces: [InterfaceCounter] = []
    var history: [HistoryEntry] = []
    var paused = false
    var snapshotDate: Date?
    var monitoringError: String?
    var bandwidthError: String?
    var storageError: String?
    var loading = true
    private let connectionService = ConnectionService()
    private let bandwidthService = BandwidthService()
    let store: HistoryStore
    private var connectionTask: Task<Void, Never>?
    private var bandwidthTask: Task<Void, Never>?
    private var lastStored: Date?
    var processes: [ProcessSummary] { ProcessSummary.group(connections) }
    var currentRate: BandwidthSample? { paused ? nil : latestRate }

    init() {
        let folder = URL.applicationSupportDirectory.appending(path: "Network Inspector", directoryHint: .isDirectory)
        store = HistoryStore(url: folder.appending(path: "history.sqlite"))
    }

    func start() {
        guard connectionTask == nil else { return }
        trace.onFinished = { [weak self] entry in await self?.save(entry) }
        health.onFinished = { [weak self] entry in await self?.save(entry) }
        connectionTask = Task { [weak self] in
            guard let self else { return }
            await refreshHistory()
            while !Task.isCancelled {
                if !paused {
                    do {
                        let rows = try await connectionService.snapshot()
                        try Task.checkCancellation()
                        if paused { continue }
                        connections = rows
                        snapshotDate = .now
                        monitoringError = nil
                        loading = false
                        if preferences.recordHistory && (lastStored == nil || Date.now.timeIntervalSince(lastStored ?? .distantPast) >= 30) {
                            lastStored = .now
                            let detail = "Periodic socket observation; not a complete flow history.\nTime\tPID\tProcess\tProtocol\tLocal\tRemote\tState\n" + rows.prefix(1000).map {
                                "\($0.observedAt.ISO8601Format())\t\($0.pid)\t\($0.process)\t\($0.transport)\t\($0.local.display)\t\($0.remoteDisplay)\t\($0.state)"
                            }.joined(separator: "\n")
                            await save(HistoryEntry(kind: .connections, title: "\(rows.count) sockets · \(ProcessSummary.group(rows).count) processes", detail: detail))
                        }
                    } catch is CancellationError { break }
                    catch { monitoringError = error.localizedDescription; loading = false }
                }
                do { try await Task.sleep(for: .seconds(preferences.pollInterval)) } catch { break }
            }
        }
        bandwidthTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if paused { await bandwidthService.reset() }
                else {
                    do {
                        let selection = preferences.selectedInterface == "automatic" ? nil : preferences.selectedInterface
                        let (snapshot, rate) = try await bandwidthService.sample(selection: selection)
                        try Task.checkCancellation()
                        if paused { latestRate = nil; continue }
                        interfaces = snapshot.interfaces
                        latestRate = rate
                        if rate == nil { bandwidth.removeAll() }
                        if let rate {
                            bandwidth.append(rate)
                            if bandwidth.count > 120 { bandwidth.removeFirst(bandwidth.count - 120) }
                        }
                        bandwidthError = nil
                        if selection != nil && !snapshot.interfaces.contains(where: { $0.name == selection && $0.isUp }) {
                            bandwidthError = "The selected interface is unavailable. Choose an active interface in Settings."
                        }
                    } catch is CancellationError { break }
                    catch { latestRate = nil; bandwidthError = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    func stop() {
        connectionTask?.cancel(); connectionTask = nil
        bandwidthTask?.cancel(); bandwidthTask = nil
        geography.cancel()
        trace.cancelIfRunning()
        health.cancel()
        paused = true
        latestRate = nil
    }

    func shutdown() async {
        let sockets = connectionTask, counters = bandwidthTask
        stop()
        async let traceStopped: Void = trace.finishCancellation()
        async let geographyStopped: Void = geography.finishCancellation()
        async let healthStopped: Void = health.finishCancellation()
        await sockets?.value
        await counters?.value
        _ = await (traceStopped, healthStopped, geographyStopped)
    }

    func togglePause() {
        paused.toggle()
        latestRate = nil
        Task { await bandwidthService.reset() }
        if !paused { bandwidth.removeAll() }
    }

    func changeInterface() {
        latestRate = nil
        bandwidth.removeAll()
        Task { await bandwidthService.reset() }
    }

    func save(_ entry: HistoryEntry) async {
        guard preferences.recordHistory else { return }
        do {
            try await store.append(entry, retentionDays: preferences.retentionDays)
            await refreshHistory()
        } catch { storageError = error.localizedDescription }
    }
    func refreshHistory() async {
        do { history = try await store.load(retentionDays: preferences.retentionDays); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    func deleteHistory() async {
        do { try await store.deleteAll(); history = []; storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    func showConnections(for host: String) { connectionSearch = host; destination = .connections }

    func investigate(_ connection: Connection) {
        guard let remote = connection.remote else { return }
        if trace.isRunning {
            trace.error = "A trace is already running. Stop it before tracing another destination."
            destination = .traceroute
            return
        }
        trace.destination = remote.host
        destination = .traceroute
        trace.run()
    }
}

@MainActor @Observable
final class TraceModel {
    var destination = ""
    var maxHops = 30
    var wait = 2
    var resolveNames = false
    var hops: [TraceHop] = []
    var output = ""
    var isRunning = false
    var status = "Ready to trace"
    var error: String?
    var selectedHop: Int?
    var onFinished: (@MainActor (HistoryEntry) async -> Void)?
    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        do { destination = try TraceDestination.validate(destination) }
        catch { self.error = error.localizedDescription; return }
        hops = []; output = ""; error = nil; selectedHop = nil; isRunning = true; status = "Discovering route…"
        let host = destination, maxHops = maxHops, wait = wait, resolveNames = resolveNames
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await TracerouteService().trace(destination: host, maxHops: maxHops, wait: wait, resolveNames: resolveNames) { [weak self] line in
                    await self?.consume(line)
                }
                if result.status != 0 { status = "Trace exited (\(result.status))" }
                else if TracerouteParser.reachedDestination(output: result.output, destination: host) {
                    status = "Destination reached · \(hops.count) \(hops.count == 1 ? "hop" : "hops")"
                } else { status = "Finished · destination did not reply" }
                if result.status != 0 { error = String(result.output.suffix(800)) }
            } catch is CancellationError { status = "Cancelled · partial results" }
            catch { status = "Trace stopped"; self.error = error.localizedDescription }
            isRunning = false
            await onFinished?(HistoryEntry(kind: .trace, title: "\(host) · \(status)", detail: output + "\n" + (error ?? "")))
        }
    }
    private func consume(_ line: String) {
        output += line + "\n"
        if let hop = TracerouteParser.parse(line) {
            hops.removeAll { $0.number == hop.number }
            hops.append(hop)
            hops.sort { $0.number < $1.number }
            if selectedHop == nil { selectedHop = hop.number }
            if isRunning { status = "Tracing · hop \(hop.number) of \(maxHops)" }
        }
    }
    func finishCancellation() async { task?.cancel(); await task?.value }
    func cancelIfRunning() { if isRunning { cancel() } }
    func cancel() { task?.cancel(); status = "Cancelling…" }
}

@MainActor @Observable
final class HealthModel {
    var destination = "example.com"
    var report: DiagnosticReport?
    var running = false
    var error: String?
    var onFinished: (@MainActor (HistoryEntry) async -> Void)?
    private var task: Task<Void, Never>?
    func run() {
        guard !running else { return }
        running = true; error = nil; report = nil
        let host = destination
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiagnosticsService().run(destination: host)
                try Task.checkCancellation()
                report = result
                await onFinished?(HistoryEntry(kind: .diagnostic, title: "Health check · \(result.destination)", detail: result.text))
            } catch is CancellationError { error = "Diagnostics cancelled." }
            catch { self.error = error.localizedDescription }
            running = false
        }
    }
    func finishCancellation() async { task?.cancel(); await task?.value }
    func cancel() { task?.cancel() }
}

@MainActor @Observable
final class ProtectionModel {
    var provider: DNSProvider
    var profiles: [ProtectionProfile]
    var selectedID: String { didSet { UserDefaults.standard.set(selectedID, forKey: "selectedProfile") } }
    var message: String?
    let capability = ProtectionCapability.inspect()
    init() {
        let defaults = UserDefaults.standard
        provider = .cloudflare
        profiles = ProtectionProfile.defaults
        selectedID = defaults.string(forKey: "selectedProfile") ?? "standard"
        do {
            if let data = defaults.data(forKey: "dnsProvider") { provider = try JSONDecoder().decode(DNSProvider.self, from: data); try provider.validate() }
            if let data = defaults.data(forKey: "profiles") {
                let stored = try JSONDecoder().decode([ProtectionProfile].self, from: data)
                guard Set(stored.map(\.id)) == Set(ProtectionProfile.defaults.map(\.id)), stored.count == 3 else { throw InspectorError.invalidInput("Invalid saved profiles.") }
                for profile in stored { _ = try profile.engine() }
                profiles = stored
            }
        } catch { message = "Saved configuration could not be loaded: \(error.localizedDescription)"; provider = .cloudflare; profiles = ProtectionProfile.defaults }
        if !profiles.contains(where: { $0.id == selectedID }) { selectedID = "standard" }
    }
    var selectedProfile: ProtectionProfile { profiles.first { $0.id == selectedID } ?? ProtectionProfile.defaults[0] }
    func saveProvider(_ newValue: DNSProvider) {
        do {
            _ = try newValue.makeSettings()
            UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: "dnsProvider")
            provider = newValue
            message = "Resolver configuration saved locally. System DNS is unchanged."
        } catch { message = error.localizedDescription }
    }
    func saveProfile(name: String, allow: String, block: String) {
        do {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw InspectorError.invalidInput("Give the profile a name of up to 80 characters.") }
            let updated = ProtectionProfile(id: selectedID, name: name, allowlist: allow, blocklist: block)
            let engine = try updated.engine()
            let revised = profiles.map { $0.id == selectedID ? updated : $0 }
            UserDefaults.standard.set(try JSONEncoder().encode(revised), forKey: "profiles")
            profiles = revised
            message = "Saved \(engine.allow.count) allow rules and \(engine.block.count) block rules. Rules are available for local testing only."
        } catch { message = "No rules changed. \(error.localizedDescription)" }
    }
    func restoreDefaults() {
        profiles = ProtectionProfile.defaults
        UserDefaults.standard.removeObject(forKey: "profiles")
        selectedID = "standard"
        message = "Restored empty, compatible profiles. No third-party blocklists are bundled."
    }
}
