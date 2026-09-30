// The sounds a track can be set to.
//
// A track stores its voice as an index, and that index is written to the
// database the web reads — so it has to mean the same thing on both sides.
// The web's list is the five synths in order, followed by a sample set it
// keeps commented out, which makes the index a preset's own position:
// REVERIE 0, PLUCKED 1, RHODES 2, ACID 3, MACHINE 4 — the web calls the
// second one KALIMBA, and the index is what the two agree on, not the word.
//
// The picker offers the presets that have voices behind them. The index
// never moves as more of them are written.
//
// After the five come the sounds made in SQIA Lab, numbered on from 5 in the
// order `Sound.library` lists them — see `TrackVoice`.

import SQIACore

enum VoiceCatalog {
    /// The original five, in the web's order.
    static var synths: [TrackVoice] { SynthPreset.available.map { .synth($0) } }

    /// The Lab's sounds, in the order they were added.
    static var sounds: [TrackVoice] { Sound.library.indices.map { .sound($0) } }

    /// The web's defaults: the two tracks start on REVERIE and MACHINE, so
    /// the mixer is useful straight away.
    static let defaultVoices = [SynthPreset.reverie.rawValue, SynthPreset.machine.rawValue]

    static func voice(at index: Int) -> TrackVoice {
        TrackVoice(index: index)
    }

    static func label(at index: Int) -> String {
        voice(at: index).label
    }
}
