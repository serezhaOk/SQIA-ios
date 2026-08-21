// The library's plumbing: rows, and the writing of them.
//
// None of this needs a server, which is the point of it being behind a
// protocol — and the cases that matter most are the ones a real server
// cannot be made to produce on demand: a save that fails because the network
// went away, an edit that lands while a write is in the air, a burst of them
// that must become one write.

import Foundation
import Testing

@testable import SQIACore

private func snapshot(bpm: Int = 120) -> ProjectSnapshot {
    ProjectSnapshot(
        bpm: bpm, rootPc: 9, scale: "minor",
        tracks: [
            TrackSnapshot(voiceIdx: 0, muted: false, grid: NoteGrid()),
            TrackSnapshot(voiceIdx: 4, muted: false, grid: NoteGrid()),
        ])
}

@Suite("Project store")
struct ProjectStoreTests {
    @Test("A new project is named, kept, and comes back")
    func createAndList() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let made = try await store.create(name: nil, snapshot: snapshot(bpm: 137))

        #expect(!made.name.isEmpty)
        #expect(made.bpm == 137)
        #expect(made.snapshot.tracks.count == 2)

        let all = try await store.list()
        #expect(all.count == 1)
        #expect(all[0].id == made.id)
    }

    @Test("The library shows the most recently written first")
    func newestFirst() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let first = try await store.create(name: "First", snapshot: snapshot())
        let second = try await store.create(name: "Second", snapshot: snapshot())

        let afterCreate = try await store.list().map(\.name)
        #expect(afterCreate == ["Second", "First"])

        // Writing to the older one brings it back to the front, which is
        // what ordering by `updated_at` does.
        try await store.save(id: first.id, snapshot: snapshot(bpm: 90))
        let afterSave = try await store.list()
        #expect(afterSave.map(\.name) == ["First", "Second"])
        #expect(afterSave[0].bpm == 90)
        _ = second
    }

    @Test("Renaming and deleting reach the row, and only that row")
    func renameAndDelete() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let keep = try await store.create(name: "Keep", snapshot: snapshot())
        let go = try await store.create(name: "Go", snapshot: snapshot())

        try await store.rename(id: keep.id, to: "Kept")
        try await store.delete(id: go.id)

        let all = try await store.list()
        #expect(all.map(\.name) == ["Kept"])

        // A row that is not there says so rather than pretending.
        await #expect(throws: ProjectStoreError.notFound) {
            try await store.delete(id: go.id)
        }
        await #expect(throws: ProjectStoreError.notFound) {
            try await store.save(id: go.id, snapshot: snapshot())
        }
    }

    @Test("A project survives the round trip the web writes it as")
    func wireFormat() async throws {
        var grid = NoteGrid()
        grid.stamp(row: 3, column: 5)
        let original = Project(
            id: "abc", name: "Wild Amoeba", bpm: 137, rootPc: 4, scale: "dorian",
            tracks: [TrackSnapshot(voiceIdx: 2, muted: true, grid: grid)],
            updatedAt: "2026-08-21T12:00:00Z")

        let data = try JSONEncoder().encode(original)
        let text = String(data: data, encoding: .utf8) ?? ""
        // The column names are the web's, and a phone writing anything else
        // would write a row a browser could not read.
        #expect(text.contains("\"root_pc\""))
        #expect(text.contains("\"updated_at\""))
        #expect(text.contains("\"voiceIdx\""))

        let restored = try JSONDecoder().decode(Project.self, from: data)
        #expect(restored == original)
        #expect(restored.snapshot.tracks[0].grid == grid)
    }
}

// The autosave's whole job is about time, which makes it the easy thing to
// test badly. An earlier version of this suite slept "long enough" and
// passed alone and failed in the full run, because a 60 ms sleep on a
// machine running thirty-three other suites comes back when it comes back.
// So: nothing here asserts that time has passed. Claims that something
// eventually happens wait for it to happen; claims that something has *not*
// happened yet are made against a window this test opens by hand.

@Suite("Autosave")
struct AutosaveTests {
    /// Only ever waited *out*, never waited *for*.
    private static let window = Duration.milliseconds(30)

    @Test("A burst of edits becomes one write, of the last one")
    func coalesces() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let project = try await store.create(name: "P", snapshot: snapshot())
        // The window stays shut until the burst is over, so this is a test
        // of coalescing and not of how fast twenty actor hops are today.
        let window = ManualWindow()
        let autosave = Autosave(delay: .seconds(1), waiting: { _ in await window.wait() })

        // Twenty edits, as a drag across the field would make.
        for bpm in 100..<120 {
            await autosave.schedule {
                try await store.save(id: project.id, snapshot: snapshot(bpm: bpm))
            }
        }
        try await settle { await window.waits == 20 }
        await window.open()
        try await settle { await autosave.saves == 1 }

        // One write reached the store, and what it wrote is the last edit.
        let begun = await store.writesStarted
        #expect(begun == 1)
        let stored = try await store.list()[0].bpm
        #expect(stored == 119)
    }

    @Test("The wait restarts on every edit")
    func debounceRestarts() async throws {
        // A window that only opens when this test opens it, so "nothing has
        // been written yet" is a fact rather than a bet on the scheduler.
        let window = ManualWindow()
        let autosave = Autosave(delay: .seconds(1), waiting: { _ in await window.wait() })
        let counter = Counter()

        for _ in 0..<5 {
            await autosave.schedule { await counter.bump() }
        }
        // Five waits began; four of them belong to timers the next edit
        // cancelled, which is what restarting the wait means.
        try await settle { await window.waits == 5 }
        let duringEdits = await counter.value
        #expect(duringEdits == 0, "wrote while the edits were still coming")

        await window.open()
        try await settle { await counter.value == 1 }
        // And the four cancelled ones stay cancelled.
        try await Task.sleep(for: Self.window)
        let afterQuiet = await counter.value
        #expect(afterQuiet == 1)
    }

    @Test("The window is waited out before anything is written")
    func waitsTheWindow() async throws {
        // The one real-clock claim, and a lower bound: a loaded machine can
        // only make this wait longer.
        let autosave = Autosave(delay: .milliseconds(120))
        let counter = Counter()
        let start = ContinuousClock.now

        await autosave.schedule { await counter.bump() }
        try await settle { await counter.value == 1 }

        #expect(ContinuousClock.now - start >= .milliseconds(120))
    }

    @Test("An edit during a write is not lost")
    func editDuringFlightIsKept() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let project = try await store.create(name: "P", snapshot: snapshot())
        // Long enough that the second edit lands mid-write — and the test
        // waits for the write to have begun rather than assuming it has.
        await store.setLatency(.milliseconds(120))
        let autosave = Autosave(delay: Self.window)

        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 100))
        }
        try await settle { await store.writesStarted == 1 }
        let writing = await autosave.isWriting
        #expect(writing)

        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 111))
        }
        try await settle { await autosave.saves == 2 }

        // Both got through, and the second edit is the one that stuck.
        let failures = await autosave.failures
        #expect(failures == 0, "a write was cancelled by the edit that followed it")
        let stored = try await store.list()[0].bpm
        #expect(stored == 111)
    }

    @Test("An edit does not cancel the write already in the air")
    func editDoesNotCancelTheWriteInFlight() async throws {
        // The reason the waiting and the writing are two tasks. A store
        // that honours cancellation — as a real request does — must not see
        // one, however many edits arrive while it is working.
        let autosave = Autosave(delay: Self.window)
        let counter = Counter()
        let started = Counter()

        await autosave.schedule {
            await started.bump()
            try await Task.sleep(for: .milliseconds(150))  // throws if cancelled
            await counter.bump()
        }
        try await settle { await started.value == 1 }
        for _ in 0..<5 { await autosave.schedule { await counter.bump() } }

        try await settle { await autosave.saves == 2 }
        let failures = await autosave.failures
        #expect(failures == 0, "the in-flight write was cancelled")
        let ran = await counter.value
        #expect(ran == 2)
    }

    @Test("A failed write is swallowed, and the next one still happens")
    func failureIsSwallowed() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let project = try await store.create(name: "P", snapshot: snapshot())
        let autosave = Autosave(delay: Self.window)

        await store.setFailure(.transport("offline"))
        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 100))
        }
        try await settle { await autosave.failures == 1 }
        let writes = await autosave.saves
        #expect(writes == 0)

        // Back on the network, the next edit writes.
        await store.setFailure(nil)
        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 128))
        }
        try await settle { await autosave.saves == 1 }
        let stored = try await store.list()[0].bpm
        #expect(stored == 128)
    }

    @Test("Flushing writes now rather than in a second and a bit")
    func flushDoesNotWait() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let project = try await store.create(name: "P", snapshot: snapshot())
        // The real delay, so this can only pass by not waiting for it.
        let autosave = Autosave()

        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 144))
        }
        await autosave.flush()

        let writes = await autosave.saves
        #expect(writes == 1)
        let stored = try await store.list()[0].bpm
        #expect(stored == 144)
    }

    @Test("Flushing waits for a write already in the air, and for what it owes")
    func flushDrainsEverything() async throws {
        let store = InMemoryProjectStore(random: Mulberry32(seed: 4))
        let project = try await store.create(name: "P", snapshot: snapshot())
        await store.setLatency(.milliseconds(80))
        let autosave = Autosave(delay: Self.window)

        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 100))
        }
        try await settle { await store.writesStarted == 1 }
        await autosave.schedule {
            try await store.save(id: project.id, snapshot: snapshot(bpm: 111))
        }
        await autosave.flush()

        // Leaving the project leaves nothing owed behind it.
        let writes = await autosave.saves
        #expect(writes == 2)
        let writing = await autosave.isWriting
        #expect(!writing)
        let stored = try await store.list()[0].bpm
        #expect(stored == 111)
    }

    @Test("A cancelled autosave writes nothing")
    func cancelDropsIt() async throws {
        let window = ManualWindow()
        let autosave = Autosave(delay: .seconds(1), waiting: { _ in await window.wait() })
        let counter = Counter()

        await autosave.schedule { await counter.bump() }
        try await settle { await window.waits == 1 }
        await autosave.cancel()
        await window.open()

        // The window is open and the timer has had its chance.
        try await Task.sleep(for: Self.window)
        let ran = await counter.value
        let writes = await autosave.saves
        #expect(ran == 0)
        #expect(writes == 0)
    }
}

/// Wait for something to become true, however loaded the machine is. The
/// deadline is only there so a genuine hang fails rather than hanging.
private func settle(
    within deadline: Duration = .seconds(10),
    _ condition: @Sendable () async -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("never settled within \(deadline)", sourceLocation: sourceLocation)
}

/// Somewhere for a job to leave a mark.
private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}

/// A debounce window that opens when the test says so. Standing in for
/// `Task.sleep`, it turns "the timer has not fired yet" from a hope into a
/// fact, and counts the waits so a restarted one is visible.
private actor ManualWindow {
    private(set) var waits = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        waits += 1
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
