// The sounds a track can be set to.
//
// A track stores its voice as an index, and that index is written to the
// database the web reads — so it has to mean the same thing on both sides.
// The web's list is the five synths in order, followed by a sample set it
// keeps commented out, which makes the index a preset's own position:
// reverie 0, plucked 1, rhodes 2, acid 3, machine 4 — the web calls the
// second one kalimba, and the index is what the two agree on, not the word.
//
// After the five come the sounds made in SQIA Lab, each under its own id —
// see `TrackVoice` and `SoundBank`. Some ship in the bundle, the rest come
// from the `sounds` table. The picker shows them all as one list: where a
// sound came from is not the listener's business.
//
// Every name is written in lower case, here and everywhere it appears.

import SQIACore

@MainActor
enum VoiceCatalog {
    /// Every sound on offer: the original five, then the rest in the order
    /// the catalogue puts them.
    static func offered(_ bank: SoundBank) -> [TrackVoice] {
        SynthPreset.available.map { .synth($0) } + bank.offered.map { .sound($0.id) }
    }

    /// The web's defaults: the two tracks start on reverie and machine, so
    /// the mixer is useful straight away.
    static let defaultVoices = [SynthPreset.reverie.rawValue, SynthPreset.machine.rawValue]

    static func voice(at index: Int) -> TrackVoice {
        TrackVoice(index: index)
    }

    static func label(_ voice: TrackVoice, _ bank: SoundBank) -> String {
        switch voice {
        case .synth(let preset): return preset.label
        // Named in a catalogue this phone has not read yet.
        case .sound(let id): return bank.sound(id)?.label ?? "…"
        }
    }

    static func hint(_ voice: TrackVoice, _ bank: SoundBank) -> String {
        switch voice {
        case .synth(let preset): return preset.hint
        case .sound(let id): return bank.sound(id)?.hint ?? ""
        }
    }

    static func isPlus(_ voice: TrackVoice, _ bank: SoundBank) -> Bool {
        if case .sound(let id) = voice { return bank.sound(id)?.plus ?? false }
        return false
    }
}
