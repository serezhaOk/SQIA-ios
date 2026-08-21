// Where projects live, behind a door.
//
// The rows are the web's — same table, same columns, same row-level security
// — and reaching them needs a session, which is M8. So everything above this
// line talks to a protocol instead: the library screen, the autosave, the
// renaming and deleting are all written and tested now, against a store that
// keeps its rows in memory, and the one that speaks to Supabase drops in
// underneath without a line above it changing.
//
// It is also what makes the awkward cases testable at all. A save that fails
// because the network went away, a list that arrives after the screen has
// moved on, a rename racing a save — none of those can be produced on
// demand against a real server.

import Foundation

public protocol ProjectStore: Sendable {
    /// Newest first, which is the order the library shows them in.
    func list() async throws -> [Project]
    /// A new project, named if a name is given and named after something
    /// microbial if not.
    func create(name: String?, snapshot: ProjectSnapshot) async throws -> Project
    func save(id: String, snapshot: ProjectSnapshot) async throws
    func rename(id: String, to name: String) async throws
    func delete(id: String) async throws
}

public enum ProjectStoreError: Error, Equatable {
    case notSignedIn
    case notFound
    /// Anything the transport reported. Kept as text because nothing above
    /// here can act on it — an autosave swallows it and the next edit tries
    /// again.
    case transport(String)
}

/// Rows in memory, for the app before it has a session and for tests.
///
/// An actor because the library screen, the autosave and a rename all reach
/// it from wherever they happen to be, and the one thing a store must never
/// do is interleave two writes into one row.
public actor InMemoryProjectStore: ProjectStore {
    private var rows: [String: Project] = [:]
    private var order: [String] = []
    private let random: RandomSource

    /// Set to have every call fail, for testing what the screen does when a
    /// network is not there.
    public var failure: ProjectStoreError?
    /// Seconds each call takes, for testing what arrives out of order.
    public var latency: Duration = .zero

    /// Writes begun and writes finished. A test that needs a second edit to
    /// land *during* a write waits for the first of these to move rather
    /// than sleeping and hoping, which on a loaded machine is a coin toss.
    public private(set) var writesStarted = 0
    public private(set) var writesFinished = 0

    public init(random: RandomSource = SystemRandomSource(), seeded: [Project] = []) {
        self.random = random
        for project in seeded {
            rows[project.id] = project
            order.append(project.id)
        }
    }

    public func setFailure(_ failure: ProjectStoreError?) { self.failure = failure }
    public func setLatency(_ latency: Duration) { self.latency = latency }

    private func gate() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if let failure { throw failure }
    }

    public func list() async throws -> [Project] {
        try await gate()
        // Newest first: the order rows were last written, reversed.
        return order.reversed().compactMap { rows[$0] }
    }

    public func create(name: String?, snapshot: ProjectSnapshot) async throws -> Project {
        try await gate()
        let project = Project(
            id: UUID().uuidString,
            name: name ?? ProjectNames.random(using: random),
            bpm: snapshot.bpm,
            rootPc: snapshot.rootPc,
            scale: snapshot.scale,
            tracks: snapshot.tracks,
            updatedAt: Self.now())
        rows[project.id] = project
        order.append(project.id)
        return project
    }

    public func save(id: String, snapshot: ProjectSnapshot) async throws {
        writesStarted += 1
        defer { writesFinished += 1 }
        try await gate()
        guard var row = rows[id] else { throw ProjectStoreError.notFound }
        row.bpm = snapshot.bpm
        row.rootPc = snapshot.rootPc
        row.scale = snapshot.scale
        row.tracks = snapshot.tracks
        row.updatedAt = Self.now()
        rows[id] = row
        touch(id)
    }

    public func rename(id: String, to name: String) async throws {
        try await gate()
        guard var row = rows[id] else { throw ProjectStoreError.notFound }
        row.name = name
        row.updatedAt = Self.now()
        rows[id] = row
        touch(id)
    }

    public func delete(id: String) async throws {
        try await gate()
        guard rows.removeValue(forKey: id) != nil else { throw ProjectStoreError.notFound }
        order.removeAll { $0 == id }
    }

    /// A written row goes to the front of the library, as ordering by
    /// `updated_at` would put it.
    private func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    /// What Postgres would write into `updated_at`.
    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
