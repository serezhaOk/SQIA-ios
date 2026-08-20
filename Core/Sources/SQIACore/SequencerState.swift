// Everything the sequencer screen is, as data.
//
// Two tracks, a key, a tempo and which track the finger is drawing on. The
// screen reads it, the transport reads it, and a saved project is this and
// nothing more — which is what lets a pattern made in a browser open on a
// phone.
//
// Port of the state and the edit operations in the web app's src/main.ts.

import Foundation

public struct TrackState: Sendable, Equatable {
    public var grid: NoteGrid
    /// Index into the app's voice list.
    public var voiceIndex: Int
    public var muted: Bool

    public init(grid: NoteGrid = NoteGrid(), voiceIndex: Int, muted: Bool = false) {
        self.grid = grid
        self.voiceIndex = voiceIndex
        self.muted = muted
    }
}

public struct SequencerState: Sendable, Equatable {
    /// Tracks start on different voices so the mixer is useful straight away.
    public static let trackCount = 2

    public static let defaultBPM = 120.0
    /// A.
    public static let defaultRootPc = 9
    /// Minor.
    public static let defaultScaleIndex = 0

    public var tracks: [TrackState]
    public var rootPc: Int
    public var scaleIndex: Int
    public var activeTrackIndex: Int
    public var bpm: Double

    public init(
        tracks: [TrackState],
        rootPc: Int = defaultRootPc,
        scaleIndex: Int = defaultScaleIndex,
        activeTrackIndex: Int = 0,
        bpm: Double = defaultBPM
    ) {
        self.tracks = tracks
        self.rootPc = rootPc
        self.scaleIndex = scaleIndex
        self.activeTrackIndex = activeTrackIndex
        self.bpm = bpm
    }

    /// A new, empty session on the given voices.
    public static func fresh(voices: [Int]) -> SequencerState {
        SequencerState(
            tracks: (0..<trackCount).map { i in
                TrackState(voiceIndex: i < voices.count ? voices[i] : 0)
            })
    }

    // ------------------------------------------------------------- the key --

    public var scale: Scale {
        Music.scales[min(max(scaleIndex, 0), Music.scales.count - 1)]
    }

    public var rootName: String {
        Music.noteNames[min(max(rootPc, 0), Music.noteNames.count - 1)]
    }

    /// The MIDI note each column plays.
    public var midiTable: [Int] {
        Music.midiTable(rootPc: rootPc, scale: scale)
    }

    /// Playback rates for a sample recorded at `baseMidi`.
    public func rateTable(baseMidi: Int = Music.defaultBaseMidi) -> [Double] {
        Music.rateTable(rootPc: rootPc, scale: scale, baseMidi: baseMidi)
    }

    public mutating func cycleRoot() {
        rootPc = (rootPc + 1) % Music.noteNames.count
    }

    public mutating func cycleScale() {
        scaleIndex = (scaleIndex + 1) % Music.scales.count
    }

    // ------------------------------------------------------------ the track --

    public var activeTrack: TrackState {
        get { tracks[safe: activeTrackIndex] ?? tracks[0] }
        set {
            guard tracks.indices.contains(activeTrackIndex) else { return }
            tracks[activeTrackIndex] = newValue
        }
    }

    public mutating func selectTrack(_ index: Int) {
        guard tracks.indices.contains(index) else { return }
        activeTrackIndex = index
    }

    /// Move to the next track — a stand-in for the mixer while it does not
    /// exist yet.
    public mutating func cycleTrack() {
        activeTrackIndex = (activeTrackIndex + 1) % tracks.count
    }

    public mutating func brush(gx: Double, gy: Double) {
        activeTrack.grid.brush(gx: gx, gy: gy)
    }

    public mutating func erase(row: Int, column: Int) {
        activeTrack.grid.erase(row: row, column: column)
    }

    public mutating func randomize(using random: RandomSource) {
        activeTrack.grid.randomize(using: random)
    }

    public mutating func toggleMute(_ index: Int) {
        guard tracks.indices.contains(index) else { return }
        tracks[index].muted.toggle()
    }

    // ---------------------------------------------------------- the project --

    public func snapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            bpm: Int(bpm.rounded()),
            rootPc: rootPc,
            scale: scale.name,
            tracks: tracks.map {
                TrackSnapshot(voiceIdx: $0.voiceIndex, muted: $0.muted, grid: $0.grid)
            }
        )
    }

    /// Load a saved project over this state.
    ///
    /// A track the snapshot does not mention keeps what it had, and a scale
    /// name we do not recognise falls back to minor — the same forgiving
    /// reading the web does, so a row written by a newer version still opens.
    public mutating func apply(_ project: ProjectSnapshot) {
        bpm = Double(project.bpm)
        rootPc = project.rootPc
        scaleIndex = Music.scales.firstIndex { $0.name == project.scale } ?? 0

        for (i, snapshot) in project.tracks.enumerated() where tracks.indices.contains(i) {
            tracks[i].voiceIndex = snapshot.voiceIdx
            tracks[i].muted = snapshot.muted
            tracks[i].grid = NoteGrid(cells: snapshot.cells)
        }
        activeTrackIndex = 0
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
