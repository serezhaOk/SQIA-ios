// The voices, and the rule that keeps them from ever repeating themselves.
//
// There is no fixture for these: Tone builds live audio nodes, which the
// generator cannot sample. What can be checked is everything the web's code
// states — the ranges every rolled value falls in, the order the values are
// drawn in, and which instrument a column turns into — and that a voice
// actually makes a sound of the right shape. Whether it sounds like the web
// is the A/B pass in M9.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

private func render(_ recipe: VoiceRecipe, frames: Int) -> [Double] {
    var voice = SynthVoice()
    voice.start(recipe, sampleRate: rate)
    return (0..<frames).map { _ in voice.render() }
}

private func rms(_ samples: [Double]) -> Double {
    guard !samples.isEmpty else { return 0 }
    return (samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)).squareRoot()
}

@Suite("Preset table")
struct PresetTests {
    @Test("Every preset has a home for its chain")
    func settingsExist() {
        for preset in SynthPreset.allCases {
            let settings = PresetSettings.of(preset)
            #expect(settings.cutoff.lowerBound < settings.cutoff.upperBound)
            #expect(settings.reverbWet.lowerBound <= settings.reverbWet.upperBound)
        }
    }

    @Test("The list is the web's, in the web's order")
    func order() {
        #expect(
            SynthPreset.allCases.map(\.label) == [
                "REVERIE", "KALIMBA", "RHODES", "ACID", "MACHINE",
            ])
    }

    @Test("Only the presets that have voices are offered")
    func available() {
        for preset in SynthPreset.available {
            let voices = SynthVoicing.notes(
                preset: preset, midi: 60, velocity: 1, using: Mulberry32(seed: 1))
            #expect(!voices.isEmpty, "\(preset.label) is offered but silent")
        }
    }

    @Test("Decibels convert the way Tone states them")
    func gains() {
        #expect(abs(VoiceRecipe.gain(db: 0) - 1) < 1e-12)
        #expect(abs(VoiceRecipe.gain(db: -6) - 0.501187) < 1e-5)
        #expect(abs(VoiceRecipe.gain(db: -12, velocity: 0.5) - 0.125594) < 1e-5)
    }
}

@Suite("REVERIE")
struct ReverieTests {
    private func roll(seed: UInt32) -> [ScheduledVoice] {
        SynthVoicing.notes(
            preset: .reverie, midi: 60, velocity: 0.9, using: Mulberry32(seed: seed))
    }

    @Test("Every rolled value lands inside the web's range")
    func ranges() {
        let random = Mulberry32(seed: 4242)
        for _ in 0..<400 {
            let voices = SynthVoicing.notes(
                preset: .reverie, midi: 60, velocity: 1, using: random)
            for voice in voices {
                let r = voice.recipe
                #expect(r.preset == .reverie)
                #expect(r.duration >= 0.06 * 0.6 && r.duration <= 0.3)
                #expect(r.release >= 0.1 * 3.2 * 0.7 && r.release <= 0.9 * 3.2)
                #expect(r.decay >= 0.08 && r.decay <= 0.5)
                #expect(r.sustain >= 0.1 && r.sustain <= 0.5)
                #expect(r.detuneCents >= -14 && r.detuneCents <= 14)
                // Attack is one of two ranges, never between them.
                #expect(
                    (r.attack >= 0.004 && r.attack <= 0.02)
                        || (r.attack >= 0.04 && r.attack <= 0.35))
                #expect(Waveform.reverieChoices.contains(r.waveform))
            }
        }
    }

    /// A ghost octave lands a moment after the note, at a fraction of its
    /// weight; a sub lands with it, an octave down.
    @Test("Extra voices are the octave above and the octave below")
    func extras() {
        var sawGhost = false
        var sawSub = false
        let random = Mulberry32(seed: 7)

        for _ in 0..<500 {
            let voices = SynthVoicing.notes(
                preset: .reverie, midi: 69, velocity: 1, using: random)
            let root = voices[0].recipe.frequency
            #expect(abs(root - 440) < 1e-9)

            for extra in voices.dropFirst() {
                if extra.recipe.frequency > root {
                    sawGhost = true
                    #expect(abs(extra.recipe.frequency - root * 2) < 1e-9)
                    #expect(extra.offset >= 0.02 && extra.offset <= 0.09)
                    #expect(extra.recipe.gain < voices[0].recipe.gain)
                } else {
                    sawSub = true
                    #expect(abs(extra.recipe.frequency - root / 2) < 1e-9)
                    #expect(extra.offset == 0)
                }
            }
        }
        #expect(sawGhost)
        #expect(sawSub)
    }

    /// The order of the draws is the port: a bare note takes eight values
    /// from the stream, and nothing may quietly take a ninth.
    @Test("A bare note consumes exactly eight values")
    func randomnessBudget() {
        // A seed whose first rolls take neither the ghost nor the sub.
        var seed: UInt32 = 0
        var found = false
        while seed < 200 && !found {
            if roll(seed: seed).count == 1 { found = true } else { seed += 1 }
        }
        #expect(found, "no seed produced a bare note")

        let random = Mulberry32(seed: seed)
        _ = SynthVoicing.notes(preset: .reverie, midi: 60, velocity: 1, using: random)
        let reference = Mulberry32(seed: seed)
        // duration, release, waveform, attack branch, attack, decay,
        // sustain, detune, then the two chances.
        for _ in 0..<10 { _ = reference.next() }
        #expect(random.next() == reference.next())
    }

    @Test("A note makes a sound and then stops making it")
    func sounds() {
        let recipe = roll(seed: 3)[0].recipe
        let out = render(recipe, frames: Int(rate * 5))
        #expect(rms(Array(out[0..<Int(rate / 10)])) > 1e-4)
        #expect(out.allSatisfy { $0.isFinite })
        #expect(out.suffix(1000).allSatisfy { $0 == 0 })
    }
}

@Suite("MACHINE")
struct MachineTests {
    private func voices(midi: Int, seed: UInt32 = 11) -> [ScheduledVoice] {
        SynthVoicing.notes(
            preset: .machine, midi: midi, velocity: 1, using: Mulberry32(seed: seed))
    }

    /// The column's register picks the instrument, so drawing a melody
    /// draws a groove.
    @Test("The register decides which drum it is")
    func registerPicksTheInstrument() {
        // Kick and tom: one pitched voice with a falling pitch.
        for midi in [48, 49, 50, 51, 52, 53] {
            let v = voices(midi: midi)
            #expect(v.count == 1)
            #expect(v[0].recipe.source == .oscillator)
            #expect(v[0].recipe.pitchOctaves > 0)
        }
        // Snare: a noise burst and a body underneath it.
        for midi in [54, 55, 56] {
            let v = voices(midi: midi)
            #expect(v.count == 2)
            #expect(v[0].recipe.source == .noise)
            #expect(v[0].recipe.filter == .bandpass)
            #expect(v[1].recipe.source == .oscillator)
        }
        // Clap: several slaps, staggered.
        for midi in [57, 58] {
            let v = voices(midi: midi)
            #expect(v.count >= 2 && v.count <= 4)
            #expect(v.allSatisfy { $0.recipe.source == .noise })
            #expect(v.last!.offset > 0)
        }
        // Metal: one inharmonic stack through a highpass.
        for midi in [59, 47] {
            let v = voices(midi: midi)
            #expect(v.count == 1)
            #expect(v[0].recipe.source == .metal)
            #expect(v[0].recipe.filter == .highpass)
        }
    }

    @Test("The same register is the same instrument in every octave")
    func octavesAgree() {
        for offset in [0, 12, 24, -12] {
            #expect(voices(midi: 48 + offset)[0].recipe.source == .oscillator)
            #expect(voices(midi: 54 + offset)[0].recipe.source == .noise)
            #expect(voices(midi: 59 + offset)[0].recipe.source == .metal)
        }
    }

    @Test("Every rolled value lands inside the web's range")
    func ranges() {
        let random = Mulberry32(seed: 31)
        for midi in 48...59 {
            for _ in 0..<60 {
                let rolled = SynthVoicing.notes(
                    preset: .machine, midi: midi, velocity: 1, using: random)
                for voice in rolled {
                    let r = voice.recipe
                    #expect(r.preset == .machine)
                    #expect(r.sustain == 0, "drums do not sustain")
                    #expect(r.duration > 0 && r.duration <= 0.6)
                    #expect(r.decay > 0 && r.decay <= 0.9)
                    #expect(r.release >= 0 && r.release <= 0.3)
                    if r.source == .metal {
                        #expect(r.harmonicity >= 3 && r.harmonicity <= 9)
                        #expect(r.modulationIndex >= 12 && r.modulationIndex <= 42)
                        #expect(r.resonance >= 2000 && r.resonance <= 7000)
                    }
                    if r.filter == .bandpass {
                        #expect(r.filterFrequency >= 900 && r.filterFrequency <= 3600)
                    }
                }
            }
        }
    }

    @Test("Every drum makes a sound of its own")
    func allSound() {
        for midi in [48, 51, 54, 57, 59] {
            for voice in voices(midi: midi) {
                let out = render(voice.recipe, frames: Int(rate * 2))
                #expect(rms(out) > 1e-5, "midi \(midi) was silent")
                #expect(out.allSatisfy { $0.isFinite })
            }
        }
    }

    /// A kick is mostly low, a hat is mostly high — the plainest statement
    /// that the register really is picking the instrument.
    @Test("A kick is low and a hat is not")
    func spectralCharacter() {
        func lowRatio(_ recipe: VoiceRecipe) -> Double {
            let out = render(recipe, frames: Int(rate))
            var filter = Biquad(lowpass: 300, sampleRate: rate)
            let low = out.map { filter.process($0) }
            return rms(low) / max(rms(out), 1e-12)
        }

        let kick = lowRatio(voices(midi: 48)[0].recipe)
        let hat = lowRatio(voices(midi: 59)[0].recipe)
        #expect(kick > 0.5, "the kick was not low: \(kick)")
        #expect(hat < 0.2, "the hat was not high: \(hat)")
    }
}

@Suite("Bar drift")
struct DriftTests {
    @Test("Every target lands inside its preset's range")
    func ranges() {
        let random = Mulberry32(seed: 5)
        for preset in SynthPreset.allCases {
            let settings = PresetSettings.of(preset)
            for _ in 0..<200 {
                let drift = SynthVoicing.drift(
                    preset: preset, bpm: 120, division: 4, using: random)
                #expect(settings.cutoff.contains(drift.cutoff))
                #expect(drift.cutoffRamp >= 0.4 && drift.cutoffRamp <= 2.5)
                #expect(drift.feedback >= 0.2 && drift.feedback <= 0.55)
                #expect(settings.reverbWet.contains(drift.reverbSend))
                #expect(drift.chorusDepthDelta >= -0.09 && drift.chorusDepthDelta <= 0.09)
            }
        }
    }

    /// An echo that has never been set always gets one; after that it moves
    /// about a quarter of the time.
    @Test("The echo is set at once, then only occasionally")
    func echoRerolls() {
        let random = Mulberry32(seed: 17)
        for _ in 0..<50 {
            #expect(
                SynthVoicing.drift(preset: .reverie, bpm: 120, division: 0, using: random)
                    .echo > 0)
        }

        var moved = 0
        let trials = 2000
        for _ in 0..<trials {
            if SynthVoicing.drift(preset: .reverie, bpm: 120, division: 4, using: random)
                .echo > 0
            {
                moved += 1
            }
        }
        let rate = Double(moved) / Double(trials)
        #expect(abs(rate - 0.25) < 0.05, "rerolled \(rate) of the time")
    }

    @Test("The echo lands on a subdivision of the beat")
    func echoIsMusical() {
        let random = Mulberry32(seed: 23)
        let step = 60.0 / 137 / 4
        for _ in 0..<200 {
            let drift = SynthVoicing.drift(
                preset: .machine, bpm: 137, division: 0, using: random)
            let divisions = (drift.echo / step).rounded()
            #expect([2.0, 3, 4, 6].contains(divisions), "landed on \(divisions)")
            #expect(abs(drift.echo - step * divisions) < 1e-12)
        }
    }

    @Test("Drift moves the chain without breaking it")
    func chainTakesDrift() {
        var chain = PresetChain(preset: .reverie, sampleRate: rate)
        let random = Mulberry32(seed: 2)
        var oscillator = Oscillator(waveform: .sine)

        for bar in 0..<8 {
            var drift = SynthVoicing.drift(
                preset: .reverie, bpm: 120, division: chain.division, using: random)
            // A bar early enough to duck the echo across the change.
            drift.lead = bar % 2 == 0 ? Int(0.08 * rate) : 0
            chain.apply(drift)

            for _ in 0..<Int(rate * 2) {
                let input = oscillator.render(frequency: 220, sampleRate: rate) * 0.3
                let out = chain.process(left: input, right: input)
                #expect(out.left.isFinite && out.right.isFinite)
                #expect(abs(out.left) < 8)
            }
        }
    }
}
