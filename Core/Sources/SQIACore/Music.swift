// Musical mapping: the grid's columns are ascending notes of the chosen
// scale, and a sample is pitched to a column by playback rate.
//
// Port of the web app's src/scales.ts.

import Foundation

public struct Scale: Sendable, Equatable, Hashable {
    public let name: String
    /// Semitone offsets within one octave.
    public let steps: [Int]

    public init(name: String, steps: [Int]) {
        self.name = name
        self.steps = steps
    }
}

public enum Music {
    public static let noteNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]

    public static let scales: [Scale] = [
        Scale(name: "minor", steps: [0, 2, 3, 5, 7, 8, 10]),
        Scale(name: "major", steps: [0, 2, 4, 5, 7, 9, 11]),
        Scale(name: "dorian", steps: [0, 2, 3, 5, 7, 9, 10]),
        Scale(name: "penta", steps: [0, 3, 5, 7, 10]),
        Scale(name: "phrygian", steps: [0, 1, 3, 5, 7, 8, 10]),
    ]

    /// Grid columns — one note each.
    public static let columns = 12

    /// Samples are recorded in C, so a column at this pitch plays untouched.
    public static let defaultBaseMidi = 60  // C4
    /// Low enough that the columns stay in a musical range.
    public static let rootBase = 48  // C3

    public static func scale(named name: String) -> Scale? {
        scales.first { $0.name == name }
    }

    /// MIDI note for a column, given the root pitch class and scale.
    public static func columnMidi(_ column: Int, rootPc: Int, scale: Scale) -> Int {
        let count = scale.steps.count
        let octave = column / count
        let offset = octave * 12 + scale.steps[column % count]
        return rootBase + rootPc + offset
    }

    /// Playback rate that pitches a sample (recorded at `baseMidi`) to a
    /// column. Only the pathological extremes are clamped — every column
    /// otherwise plays true pitch.
    public static func columnRate(
        _ column: Int,
        rootPc: Int,
        scale: Scale,
        baseMidi: Int = defaultBaseMidi
    ) -> Double {
        let midi = columnMidi(column, rootPc: rootPc, scale: scale)
        let rate = exp2(Double(midi - baseMidi) / 12)
        return min(4, max(0.25, rate))
    }

    public static func rateTable(
        rootPc: Int,
        scale: Scale,
        baseMidi: Int = defaultBaseMidi
    ) -> [Double] {
        (0..<columns).map { columnRate($0, rootPc: rootPc, scale: scale, baseMidi: baseMidi) }
    }

    /// Concert pitch: A above middle C is MIDI 69 at 440 Hz.
    public static func frequency(ofMidi midi: Int) -> Double {
        440 * exp2(Double(midi - 69) / 12)
    }

    public static func midiTable(rootPc: Int, scale: Scale) -> [Int] {
        (0..<columns).map { columnMidi($0, rootPc: rootPc, scale: scale) }
    }

    /// The columns a drum kit is laid out on, which is not a key at all.
    ///
    /// MACHINE picks its instrument from `midi % 12` — low columns are kicks
    /// and toms, the middle is snare and clap, the top is metal. Run that
    /// through a key and the whole kit slides: change the root by three and
    /// the kicks you drew become toms. The pattern is still there and it is
    /// no longer the pattern.
    ///
    /// So a drum track can be given a chromatic run instead, where a column
    /// is always the same instrument. It is a departure from the web, which
    /// transposes everything alike, and it is one worth making.
    public static let drumTable: [Int] = (0..<columns).map { rootBase + $0 }
}
