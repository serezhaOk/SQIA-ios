// The sounds a track can be set to.
//
// The web app's list is synths first, then a sample set it currently keeps
// commented out. The synths arrive with M5; until then the samples are what
// there is, so they are what the picker offers. When the synths land they go
// in front and the samples go back to being parked, and the list matches the
// web exactly.

import SQIACore

struct Voice: Identifiable, Equatable {
    /// Bundle name of the sample, without the extension.
    let file: String
    let label: String
    let hint: String
    /// Samples are recorded in C; this only moves for one cut in another
    /// octave.
    var baseMidi: Int = Music.defaultBaseMidi

    var id: String { file }
}

enum VoiceCatalog {
    /// Labels and order are the web app's, from the parked list in
    /// src/samples.ts.
    static let all: [Voice] = [
        Voice(file: "bell-kalimbox", label: "KALIMBOX", hint: "Sample"),
        Voice(file: "keys-synth", label: "KEYS SYNTH", hint: "Sample"),
        Voice(file: "grand-piano-low", label: "PIANO LOW", hint: "Sample"),
        Voice(file: "grand-piano-high", label: "PIANO HIGH", hint: "Sample"),
        Voice(file: "horn-synth", label: "HORN SYNTH", hint: "Sample"),
        Voice(file: "ikembe", label: "IKEMBE", hint: "Sample"),
        Voice(file: "bell-evolving", label: "EVOLVING", hint: "Sample"),
        Voice(file: "bell-lovely", label: "LOVELY", hint: "Sample"),
        Voice(file: "bell-toy-piano", label: "TOY PIANO", hint: "Sample"),
        Voice(file: "bell-ring", label: "RING BELL", hint: "Sample"),
        Voice(file: "synth-round-five", label: "ROUND FIVE", hint: "Sample"),
        Voice(file: "westafrica-ngona", label: "NGONA", hint: "Sample"),
        Voice(file: "bells-agogo", label: "AGOGO", hint: "Sample"),
        Voice(file: "cowbell", label: "COWBELL", hint: "Sample"),
        Voice(file: "conga-low", label: "CONGA", hint: "Sample"),
        Voice(file: "bongo-low", label: "BONGO", hint: "Sample"),
    ]

    /// What the two tracks start on. The web starts on REVERIE and MACHINE;
    /// these are the nearest thing the sample set has to a melody and a
    /// drum, and they go back to the synths in M5.
    static let defaultVoices = [0, 15]

    static func voice(at index: Int) -> Voice {
        all[min(max(index, 0), all.count - 1)]
    }

    static func label(at index: Int) -> String {
        voice(at: index).label
    }
}
