// What a saved project looks like on the wire.
//
// This is the one format that must not drift: iOS and the web read and write
// the same rows, so a project made on a phone has to open in a browser and
// the other way round. Keys are the web app's, spelling included.
//
// Postgres stores the pattern as jsonb and normalises the text, so what has
// to match between platforms is the values, not the byte layout.

import Foundation

public struct TrackSnapshot: Codable, Sendable, Equatable {
    /// Index into the app's voice list (synths first, then samples).
    public var voiceIdx: Int
    public var muted: Bool
    /// Row-major intensities, `NoteGrid.count` of them, rounded to two decimals.
    public var cells: [Double]

    public init(voiceIdx: Int, muted: Bool, cells: [Double]) {
        self.voiceIdx = voiceIdx
        self.muted = muted
        self.cells = cells
    }

    public init(voiceIdx: Int, muted: Bool, grid: NoteGrid) {
        self.init(voiceIdx: voiceIdx, muted: muted, cells: ProjectSnapshot.encode(grid))
    }

    public var grid: NoteGrid {
        NoteGrid(cells: cells)
    }
}

public struct ProjectSnapshot: Codable, Sendable, Equatable {
    public var bpm: Int
    public var rootPc: Int
    public var scale: String
    public var tracks: [TrackSnapshot]

    enum CodingKeys: String, CodingKey {
        case bpm
        case rootPc = "root_pc"
        case scale
        case tracks
    }

    public init(bpm: Int, rootPc: Int, scale: String, tracks: [TrackSnapshot]) {
        self.bpm = bpm
        self.rootPc = rootPc
        self.scale = scale
        self.tracks = tracks
    }

    /// Two decimals is plenty for an intensity and keeps the row small.
    ///
    /// Cells are never negative, so rounding half away from zero is the same
    /// as JavaScript's `Math.round` (which rounds half toward +∞).
    public static func encode(_ grid: NoteGrid) -> [Double] {
        grid.cells.map { (Double($0) * 100).rounded(.toNearestOrAwayFromZero) / 100 }
    }
}

/// A project as stored, including the fields the server owns.
public struct Project: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var bpm: Int
    public var rootPc: Int
    public var scale: String
    public var tracks: [TrackSnapshot]
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bpm
        case rootPc = "root_pc"
        case scale
        case tracks
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        name: String,
        bpm: Int,
        rootPc: Int,
        scale: String,
        tracks: [TrackSnapshot],
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.rootPc = rootPc
        self.scale = scale
        self.tracks = tracks
        self.updatedAt = updatedAt
    }

    public var snapshot: ProjectSnapshot {
        ProjectSnapshot(bpm: bpm, rootPc: rootPc, scale: scale, tracks: tracks)
    }
}
