import Foundation
import Testing
@testable import NetworkCore

struct PersistenceTests {
    @Test func roundTripRetentionAndDeletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "inspector-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "history.sqlite")
        let store = HistoryStore(url: url)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = HistoryEntry(date: now.addingTimeInterval(-10 * 86400), kind: .connections, title: "Expired", detail: "old")
        try await store.append(old, retentionDays: 30, now: now)
        let fresh = HistoryEntry(date: now, kind: .trace, title: "Recent", detail: "hop output")
        try await store.append(fresh, retentionDays: 7, now: now)
        let reopened = HistoryStore(url: url)
        let loaded = try await reopened.load(retentionDays: 7, now: now)
        #expect(loaded.map(\.id) == [fresh.id])
        #expect(loaded.first?.detail == "hop output")
        try await reopened.deleteAll()
        #expect(try await reopened.load(now: now).isEmpty)
    }
    @Test func historyCountAndRecordSizeAreBounded() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "inspector-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(url: folder.appending(path: "history.sqlite"))
        let now = Date.now
        for index in 0..<6 {
            try await store.append(HistoryEntry(date: now.addingTimeInterval(Double(index)), kind: .diagnostic, title: "\(index)", detail: "result"), retentionDays: 7, limit: 3, now: now)
        }
        #expect(try await store.load(now: now).map(\.title) == ["5", "4", "3"])
        #expect(HistoryEntry(kind: .trace, title: "Unicode", detail: String(repeating: "🦉", count: 100_000)).detail.utf8.count <= 262_144)
        #expect(HistoryEntry(kind: .trace, title: "Large", detail: String(repeating: "x", count: 300_000)).detail.count == 262_144)
    }
    @Test func totalHistoryPayloadIsBounded() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "inspector-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(url: folder.appending(path: "history.sqlite"))
        let now = Date.now
        for index in 0..<132 {
            try await store.append(HistoryEntry(date: now.addingTimeInterval(Double(index)), kind: .trace, title: "\(index)", detail: String(repeating: "x", count: 262_144)), retentionDays: 7, now: now)
        }
        let rows = try await store.load(now: now)
        #expect(rows.count < 128)
        #expect(rows.first?.title == "131")
        #expect(rows.reduce(0) { $0 + $1.detail.utf8.count } < 33_554_432)
    }
    @Test func corruptDatabaseReturnsExplicitError() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "inspector-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "history.sqlite")
        try Data("not a SQLite database".utf8).write(to: url)
        let store = HistoryStore(url: url)
        await #expect(throws: InspectorError.self) { try await store.load() }
    }
}
