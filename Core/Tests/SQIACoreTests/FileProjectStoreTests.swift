// The library on disk: it has to still be there after the app is killed,
// and it has to open when the file is not what it expected.

import Foundation
import Testing

@testable import SQIACore

private func snapshot(bpm: Int = 120) -> ProjectSnapshot {
    ProjectSnapshot(
        bpm: bpm, rootPc: 9, scale: "minor",
        tracks: [TrackSnapshot(voiceIdx: 0, muted: false, grid: NoteGrid())])
}

/// A file of its own per test, cleaned up after.
private func temporaryURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sqia-test-\(UUID().uuidString).json")
}

@Suite("Library on disk")
struct FileProjectStoreTests {
    @Test("What was written is there when the app comes back")
    func survivesRelaunch() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = FileProjectStore(url: url, random: Mulberry32(seed: 4))
        let made = try await first.create(name: "Kept", snapshot: snapshot(bpm: 137))
        try await first.save(id: made.id, snapshot: snapshot(bpm: 91))

        // A different store over the same file is what a relaunch is.
        let second = FileProjectStore(url: url, random: Mulberry32(seed: 4))
        let all = try await second.list()
        #expect(all.count == 1)
        #expect(all[0].name == "Kept")
        #expect(all[0].bpm == 91)
        #expect(all[0].id == made.id)
    }

    @Test("The most recently written comes first")
    func newestFirst() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProjectStore(url: url, random: Mulberry32(seed: 4))

        let first = try await store.create(name: "First", snapshot: snapshot())
        _ = try await store.create(name: "Second", snapshot: snapshot())
        let afterCreate = try await store.list().map(\.name)
        #expect(afterCreate == ["Second", "First"])

        try await store.save(id: first.id, snapshot: snapshot(bpm: 90))
        let afterSave = try await store.list().map(\.name)
        #expect(afterSave == ["First", "Second"])
    }

    @Test("Renaming does not reorder the library")
    func renameKeepsPlace() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProjectStore(url: url, random: Mulberry32(seed: 4))

        let first = try await store.create(name: "First", snapshot: snapshot())
        _ = try await store.create(name: "Second", snapshot: snapshot())
        try await store.rename(id: first.id, to: "Renamed")

        let all = try await store.list().map(\.name)
        #expect(all == ["Second", "Renamed"])
    }

    @Test("Deleting reaches that row and only that row")
    func deletes() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProjectStore(url: url, random: Mulberry32(seed: 4))

        let keep = try await store.create(name: "Keep", snapshot: snapshot())
        let go = try await store.create(name: "Go", snapshot: snapshot())
        try await store.delete(id: go.id)

        let all = try await store.list().map(\.name)
        #expect(all == ["Keep"])
        _ = keep

        await #expect(throws: ProjectStoreError.notFound) {
            try await store.delete(id: go.id)
        }
        await #expect(throws: ProjectStoreError.notFound) {
            try await store.rename(id: go.id, to: "Nope")
        }
    }

    @Test("A file from another version opens as an empty library, not a crash")
    func unreadableFileOpensEmpty() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ this is not a library ".utf8).write(to: url)

        let store = FileProjectStore(url: url, random: Mulberry32(seed: 4))
        let all = try await store.list()
        #expect(all.isEmpty)

        // And it is writable again from there.
        _ = try await store.create(name: "Fresh", snapshot: snapshot())
        let after = try await store.list().map(\.name)
        #expect(after == ["Fresh"])
    }

    @Test("A library that was never written is empty rather than missing")
    func noFileYet() async throws {
        let url = temporaryURL()
        let store = FileProjectStore(url: url, random: Mulberry32(seed: 4))
        let all = try await store.list()
        #expect(all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("An unnamed project gets one of the microbial names")
    func namesItself() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProjectStore(url: url, random: Mulberry32(seed: 4))

        let made = try await store.create(name: nil, snapshot: snapshot())
        #expect(!made.name.isEmpty)
    }
}
