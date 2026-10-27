import SwiftUI
import Observation

@MainActor @Observable
final class GeographyModel {
    var locations: [String: IPLocation] = [:]
    var origin: IPLocation?
    var running = false
    var completed = 0
    var total = 0
    var error: String?
    var summary: String?
    private let service = IPGeolocationService()
    private var task: Task<Void, Never>?

    var currentOrigin: IPLocation? { origin.flatMap { Date.now.timeIntervalSince($0.fetchedAt) < 86400 ? $0 : nil } }

    func location(_ host: String) -> IPLocation? {
        guard let key = IPAddress(host)?.canonical, let value = locations[key], Date.now.timeIntervalSince(value.fetchedAt) < 86400 else { return nil }
        return value
    }
    func pending(_ addresses: [String]) -> [String] {
        Array(Set(addresses.compactMap(IPAddress.init).filter(\.isPublic).map(\.canonical)))
            .filter { location($0) == nil }.sorted().prefix(64).map { $0 }
    }
    /// No remembered consent: each action is scoped to the addresses disclosed in its popover.
    func locate(_ approvedAddresses: [String]) {
        guard !running else { return }
        let addresses = pending(approvedAddresses)
        running = true; completed = 0; total = addresses.count + (currentOrigin == nil ? 1 : 0); error = nil; summary = nil
        task = Task { [weak self] in
            guard let self else { return }
            var failures = 0
            if currentOrigin == nil {
                do { origin = try await service.locate(nil) }
                catch is CancellationError { running = false; return }
                catch GeoLookupError.rateLimited { error = GeoLookupError.rateLimited.localizedDescription; running = false; return }
                catch { failures += 1; self.error = error.localizedDescription }
                completed += 1
            }
            for address in addresses {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    let value = try await service.locate(address)
                    try Task.checkCancellation()
                    locations[address] = value
                    if locations.count > 512, let oldest = locations.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { locations.removeValue(forKey: oldest) }
                } catch is CancellationError { break }
                catch GeoLookupError.rateLimited { failures += 1; self.error = GeoLookupError.rateLimited.localizedDescription; break }
                catch { failures += 1; self.error = error.localizedDescription }
                completed += 1
            }
            summary = Task.isCancelled ? "Location lookup stopped." : failures == 0 ? "Locations updated. Estimates from IPWHOIS.io." : "\(failures) \(failures == 1 ? "lookup was" : "lookups were") unavailable. Other results are shown."
            running = false
        }
    }
    func cancel() { task?.cancel() }
    func finishCancellation() async { task?.cancel(); await task?.value }
    func clear() {
        guard !running else { return }
        locations = [:]; origin = nil; summary = nil; error = nil
    }
}
