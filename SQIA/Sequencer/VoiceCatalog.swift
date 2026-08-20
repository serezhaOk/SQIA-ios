// The sounds a track can be set to.
//
// A track stores its voice as an index, and that index is written to the
// database the web reads — so it has to mean the same thing on both sides.
// The web's list is the five synths in order, followed by a sample set it
// keeps commented out, which makes the index a preset's own position:
// REVERIE 0, KALIMBA 1, RHODES 2, ACID 3, MACHINE 4.
//
// The picker offers the presets that have voices behind them. The index
// never moves as more of them are written.

import SQIACore

enum VoiceCatalog {
    /// What the picker shows, in the web's order.
    static var offered: [SynthPreset] { SynthPreset.available }

    /// The web's defaults: the two tracks start on REVERIE and MACHINE, so
    /// the mixer is useful straight away.
    static let defaultVoices = [SynthPreset.reverie.rawValue, SynthPreset.machine.rawValue]

    static func preset(at index: Int) -> SynthPreset {
        SynthPreset(rawValue: index) ?? .reverie
    }

    static func index(of preset: SynthPreset) -> Int {
        preset.rawValue
    }

    static func label(at index: Int) -> String {
        preset(at: index).label
    }
}
