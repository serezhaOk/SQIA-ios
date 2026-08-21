// Rows in a file on the phone.
//
// The web has no local copy at all: Supabase or nothing. A phone cannot
// afford that — it is offline in lifts and on trains, and a sequencer that
// loses the pattern somebody drew because a request failed is not one they
// will open again.
//
// So this is where the library lives until M8, and after M8 it stays as the
// thing the Supabase store falls back to and syncs against. One file, whole
// on every write: the library is small, the write is rare, and the failure
// mode of half a file is worse than any speed it would buy.

import Foundation

public actor FileProjectStore: ProjectStore {
    private let url: URL
    private let random: RandomSource
    private var rows: [Project]?

    /// Where the library goes when nobody says otherwise.
    public static func defaultURL() -> URL {
        let base =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("sqia-projects.json")
    }

    public init(url: URL? = nil, random: RandomSource = SystemRandomSource()) {
        self.url = url ?? Self.defaultURL()
        self.random = random
    }

    public func list() async throws -> [Project] {
        try loaded()
    }

    public func create(name: String?, snapshot: ProjectSnapshot) async throws -> Project {
        var all = try loaded()
        let project = Project(
            id: UUID().uuidString,
            name: name ?? ProjectNames.random(using: random),
            bpm: snapshot.bpm,
            rootPc: snapshot.rootPc,
            scale: snapshot.scale,
            tracks: snapshot.tracks,
            updatedAt: Self.now())
        all.insert(project, at: 0)
        try write(all)
        return project
    }

    public func save(id: String, snapshot: ProjectSnapshot) async throws {
        var all = try loaded()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw ProjectStoreError.notFound
        }
        var row = all.remove(at: index)
        row.bpm = snapshot.bpm
        row.rootPc = snapshot.rootPc
        row.scale = snapshot.scale
        row.tracks = snapshot.tracks
        row.updatedAt = Self.now()
        // Written means newest, which is where the library shows it.
        all.insert(row, at: 0)
        try write(all)
    }

    public func rename(id: String, to name: String) async throws {
        var all = try loaded()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw ProjectStoreError.notFound
        }
        all[index].name = name
        all[index].updatedAt = Self.now()
        try write(all)
    }

    public func delete(id: String) async throws {
        var all = try loaded()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw ProjectStoreError.notFound
        }
        all.remove(at: index)
        try write(all)
    }

    // ------------------------------------------------------------- the file --

    private func loaded() throws -> [Project] {
        if let rows { return rows }
        guard let data = try? Data(contentsOf: url) else {
            rows = []
            return []
        }
        // A file we cannot read is a file from a version that is not this
        // one, or a half-written one from a crash. Either way the honest
        // answer is an empty library rather than a screen that will not open.
        let decoded = (try? JSONDecoder().decode([Project].self, from: data)) ?? []
        rows = decoded
        return decoded
    }

    private func write(_ all: [Project]) throws {
        rows = all
        do {
            let data = try JSONEncoder().encode(all)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ProjectStoreError.transport(error.localizedDescription)
        }
    }

    /// The same shape Postgres writes into `updated_at`, so a row that came
    /// from here and a row that came from the server sort together.
    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
