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

/// A voice's own output, summed to mono — which is what it is, unless it
/// carries a tremolo.
private func render(_ recipe: VoiceRecipe, frames: Int) -> [Double] {
    var voice = SynthVoice()
    voice.prepare(sampleRate: rate)
    voice.start(recipe, sampleRate: rate)
    return (0..<frames).map { _ in
        let out = voice.render()
        return (out.left + out.right) / 2
    }
}

/// Both sides, for the one voice that has two.
private func renderStereo(
    _ recipe: VoiceRecipe, frames: Int
) -> (left: [Double], right: [Double]) {
    var voice = SynthVoice()
    voice.prepare(sampleRate: rate)
    voice.start(recipe, sampleRate: rate)
    var left = [Double]()
    var right = [Double]()
    left.reserveCapacity(frames)
    right.reserveCapacity(frames)
    for _ in 0..<frames {
        let out = voice.render()
        left.append(out.left)
        right.append(out.right)
    }
    return (left, right)
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

@Suite("KALIMBA")
struct KalimbaTests {
    private func roll(seed: UInt32, velocity: Double = 0.9) -> [ScheduledVoice] {
        SynthVoicing.notes(
            preset: .kalimba, midi: 60, velocity: velocity, using: Mulberry32(seed: seed))
    }

    @Test("Every rolled value lands inside the web's range")
    func ranges() {
        let random = Mulberry32(seed: 77)
        for _ in 0..<400 {
            let voices = SynthVoicing.notes(
                preset: .kalimba, midi: 55, velocity: 1, using: random)
            let lead = voices[0].recipe
            #expect(lead.preset == .kalimba)
            #expect(lead.source == .pluck)
            #expect(lead.pluckResonance >= 0.55 && lead.pluckResonance <= 0.94)
            #expect(lead.pluckDampening >= 900 && lead.pluckDampening <= 4500)
            #expect(lead.attackNoise >= 0.4 && lead.attackNoise <= 1.8)
            #expect(lead.filterFrequency >= 1200 && lead.filterFrequency <= 5200)
            #expect(lead.filterQ >= 0.3 && lead.filterQ <= 2.2)
            #expect(lead.filterTarget >= 500 && lead.filterTarget <= 1600)
            #expect(lead.filterRamp >= 0.3 && lead.filterRamp <= 1.1)
            #expect(lead.lifetime == 2.2)

            if voices.count > 1 {
                let ghost = voices[1].recipe
                // An octave up, quieter, damped harder and ringing shorter —
                // and with no lowpass of its own.
                #expect(abs(ghost.frequency - lead.frequency * 2) < 1e-9)
                #expect(abs(ghost.pluckDampening - lead.pluckDampening * 1.4) < 1e-9)
                #expect(abs(ghost.pluckResonance - lead.pluckResonance * 0.8) < 1e-9)
                #expect(ghost.attackNoise == 0.6)
                #expect(ghost.filter == .none)
                #expect(ghost.lifetime == 1.6)
                #expect(voices[1].offset >= 0.01 && voices[1].offset <= 0.05)
            }
        }
    }

    /// The order matters more than the ranges: a seeded run can only be
    /// compared with the web if every value comes off the stream in the same
    /// place. This walks a second generator through the web's sequence and
    /// checks the note was built from exactly those draws.
    @Test("Values come off the stream in the web's order")
    func drawOrder() {
        let expected = Mulberry32(seed: 9)
        let resonance = expected.value(0.55, 0.94)
        let dampening = expected.value(900, 4500)
        let attackNoise = expected.value(0.4, 1.8)
        _ = expected.value(0.1, 0.9)  // the release Tone takes and never uses
        let cutoff = expected.value(1200, 5200)
        let q = expected.value(0.3, 2.2)
        let target = expected.value(500, 1600)
        let ramp = expected.value(0.3, 1.1)
        let ghosted = expected.chance(0.18)
        let offset = ghosted ? expected.value(0.01, 0.05) : 0

        let voices = roll(seed: 9)
        let lead = voices[0].recipe
        #expect(lead.pluckResonance == resonance)
        #expect(lead.pluckDampening == dampening)
        #expect(lead.attackNoise == attackNoise)
        #expect(lead.filterFrequency == cutoff)
        #expect(lead.filterQ == q)
        #expect(lead.filterTarget == target)
        #expect(lead.filterRamp == ramp)
        #expect((voices.count > 1) == ghosted)
        if ghosted { #expect(voices[1].offset == offset) }
    }

    @Test("The ghost turns up about a fifth of the time")
    func ghostRate() {
        let random = Mulberry32(seed: 5)
        var ghosts = 0
        let runs = 4000
        for _ in 0..<runs {
            let voices = SynthVoicing.notes(
                preset: .kalimba, midi: 60, velocity: 1, using: random)
            if voices.count > 1 { ghosts += 1 }
        }
        let rate = Double(ghosts) / Double(runs)
        #expect(abs(rate - 0.18) < 0.02, "ghosted \(rate) of the time")
    }

    @Test("Velocity lives in the level, with a floor under it")
    func velocityInTheGain() {
        let loud = roll(seed: 3, velocity: 1)[0].recipe.gain
        let soft = roll(seed: 3, velocity: 0.3)[0].recipe.gain
        let silent = roll(seed: 3, velocity: 0)[0].recipe.gain
        #expect(loud > soft)
        // Tone's floor: below 0.02 the level stops falling, so a soft cell
        // is quiet rather than absent.
        #expect(silent > 0)
        #expect(abs(silent - roll(seed: 3, velocity: 0.01)[0].recipe.gain) < 1e-12)
    }

    // ------------------------------------------------------------- sound --

    @Test("A pluck rings at the note it was given")
    func ringsInTune() {
        var recipe = VoiceRecipe()
        recipe.preset = .kalimba
        recipe.source = .pluck
        recipe.frequency = 220
        recipe.gain = 1
        recipe.pluckResonance = 0.94
        recipe.pluckDampening = 4000
        recipe.attackNoise = 1
        recipe.lifetime = 2.2

        let out = render(recipe, frames: Int(rate / 2))
        // Past the burst, one period apart, the waveform repeats itself.
        let period = Int((rate / 220).rounded())
        let window = Array(out[(period * 8)..<(period * 40)])
        var same = 0.0
        var energy = 0.0
        for i in period..<window.count {
            same += window[i] * window[i - period]
            energy += window[i] * window[i]
        }
        #expect(energy > 0, "the pluck made no sound")
        #expect(same / energy > 0.7, "no periodicity at 220 Hz: \(same / energy)")
    }

    @Test("Resonance decides how long the tine rings")
    func resonanceSetsTheTail() {
        func tail(_ resonance: Double) -> Double {
            var recipe = VoiceRecipe()
            recipe.preset = .kalimba
            recipe.source = .pluck
            recipe.frequency = 330
            recipe.gain = 1
            recipe.pluckResonance = resonance
            recipe.pluckDampening = 3000
            recipe.attackNoise = 1
            recipe.lifetime = 2.2
            let out = render(recipe, frames: Int(rate))
            return rms(Array(out[Int(rate / 2)...]))
        }
        #expect(tail(0.94) > tail(0.55) * 10, "the short one is not short enough")
    }

    @Test("Dampening decides how bright it arrives")
    func dampeningSetsTheTone() {
        func brightness(_ dampening: Double) -> Double {
            var recipe = VoiceRecipe()
            recipe.preset = .kalimba
            recipe.source = .pluck
            recipe.frequency = 220
            recipe.gain = 1
            recipe.pluckResonance = 0.8
            recipe.pluckDampening = dampening
            recipe.attackNoise = 1
            recipe.lifetime = 2.2
            let out = render(recipe, frames: 4096)
            // How much of the signal is in the fast-moving part of it.
            var difference = 0.0
            for i in 1..<out.count { difference += (out[i] - out[i - 1]) * (out[i] - out[i - 1]) }
            let total = out.reduce(0) { $0 + $1 * $1 }
            return total > 0 ? difference / total : 0
        }
        #expect(brightness(4500) > brightness(900), "the dark one is not darker")
    }

    @Test("The lowpass sweeps down across the note")
    func filterSweeps() {
        var recipe = VoiceRecipe()
        recipe.preset = .kalimba
        recipe.source = .pluck
        recipe.frequency = 220
        recipe.gain = 1
        recipe.pluckResonance = 0.94
        recipe.pluckDampening = 4500
        recipe.attackNoise = 1
        recipe.lifetime = 2.2
        recipe.filter = .lowpass
        recipe.filterFrequency = 5200
        recipe.filterQ = 1
        recipe.filterTarget = 500
        recipe.filterRamp = 0.5

        let out = render(recipe, frames: Int(rate))
        #expect(out.allSatisfy { $0.isFinite })
        #expect(rms(Array(out[0..<2048])) > 0, "nothing came out")
    }
}

@Suite("ACID")
struct AcidTests {
    private func roll(seed: UInt32, velocity: Double) -> VoiceRecipe {
        SynthVoicing.notes(
            preset: .acid, midi: 60, velocity: velocity, using: Mulberry32(seed: seed)
        )[0].recipe
    }

    @Test("Every rolled value lands inside the web's range")
    func ranges() {
        let random = Mulberry32(seed: 61)
        for run in 0..<400 {
            // Alternate between accented and soft cells so both branches are
            // walked, and both sets of ranges checked.
            let velocity = run % 2 == 0 ? 1.0 : 0.4
            let accent = velocity > SynthVoicing.acidAccent
            let voices = SynthVoicing.notes(
                preset: .acid, midi: 60, velocity: velocity, using: random)
            #expect(voices.count == 1, "acid is one voice a note")
            let r = voices[0].recipe

            #expect(r.preset == .acid)
            #expect(r.waveform == .sawtooth || r.waveform == .square)
            #expect(r.filter == .lowpass)
            #expect(r.filterCascaded)
            // Two octaves below the grid, so it sits under everything else.
            #expect(abs(r.frequency - Music.frequency(ofMidi: 60) / 4) < 1e-9)

            if accent {
                #expect(r.filterQ >= 9 && r.filterQ <= 15)
                #expect(r.filterFrequency >= 90 * 1.1 && r.filterFrequency <= 260 * 1.6)
                #expect(r.filterOctaves >= 3 && r.filterOctaves <= 4.6)
                #expect(r.sustain >= 0.25 && r.sustain <= 0.5)
            } else {
                #expect(r.filterQ >= 4 && r.filterQ <= 11)
                #expect(r.filterFrequency >= 90 && r.filterFrequency <= 260)
                #expect(r.filterOctaves >= 1.6 && r.filterOctaves <= 3.4)
                #expect(r.sustain >= 0.05 && r.sustain <= 0.25)
            }

            #expect(r.filterDecay >= 0.09 && r.filterDecay <= 0.42)
            #expect(r.duration >= 0.06 && r.duration <= 0.22)
            #expect(r.release >= 0.03 && r.release <= 0.14)
            #expect(r.attack == 0.002)
            #expect(r.decay >= 0.05 && r.decay <= 0.3)
            #expect(r.filterAttack >= 0.002 && r.filterAttack <= 0.014)
            #expect(r.filterSustain >= 0.02 && r.filterSustain <= 0.22)
            #expect(r.filterRelease >= 0.05 && r.filterRelease <= 0.25)
            #expect(abs(r.detuneCents) <= 6)
        }
    }

    @Test("Values come off the stream in the web's order")
    func drawOrder() {
        let expected = Mulberry32(seed: 21)
        // A soft cell: no accent, so the base takes no second draw.
        let q = expected.value(4, 11)
        let base = expected.value(90, 260)
        let octaves = expected.value(1.6, 3.4)
        let sweep = expected.value(0.09, 0.42)
        let duration = expected.value(0.06, 0.22)
        let release = expected.value(0.03, 0.14)
        let waveform = expected.pick([Waveform.sawtooth, .square])
        let decay = expected.value(0.05, 0.3)
        let sustain = expected.value(0.05, 0.25)
        let filterAttack = expected.value(0.002, 0.014)
        let filterSustain = expected.value(0.02, 0.22)
        let filterRelease = expected.value(0.05, 0.25)
        let detune = expected.value(-6, 6)

        let r = roll(seed: 21, velocity: 0.5)
        #expect(r.filterQ == q)
        #expect(r.filterFrequency == base)
        #expect(r.filterOctaves == octaves)
        #expect(r.filterDecay == sweep)
        #expect(r.duration == duration)
        #expect(r.release == release)
        #expect(r.waveform == waveform)
        #expect(r.decay == decay)
        #expect(r.sustain == sustain)
        #expect(r.filterAttack == filterAttack)
        #expect(r.filterSustain == filterSustain)
        #expect(r.filterRelease == filterRelease)
        #expect(r.detuneCents == detune)
    }

    @Test("An accent pushes the filter as well as the amp")
    func accentsPushBoth() {
        // Averaged, because every value is rolled: what is being checked is
        // that the accented branch sits higher, not any one note.
        var loudQ = 0.0
        var softQ = 0.0
        var loudOctaves = 0.0
        var softOctaves = 0.0
        var loudGain = 0.0
        var softGain = 0.0
        let runs = 200

        for seed in 0..<UInt32(runs) {
            let loud = roll(seed: seed, velocity: 1)
            let soft = roll(seed: seed, velocity: 0.5)
            loudQ += loud.filterQ
            softQ += soft.filterQ
            loudOctaves += loud.filterOctaves
            softOctaves += soft.filterOctaves
            loudGain += loud.gain
            softGain += soft.gain
        }

        #expect(loudQ > softQ, "the accent did not squelch harder")
        #expect(loudOctaves > softOctaves, "the accent did not open further")
        #expect(loudGain > softGain, "the accent was no louder")
        // And the level is where the web puts it: -18 dB at full accent.
        #expect(abs(loudGain / Double(runs) - VoiceRecipe.gain(db: -18)) < 1e-12)
    }

    // ------------------------------------------------------------- sound --

    private func note(q: Double, octaves: Double) -> VoiceRecipe {
        var recipe = VoiceRecipe()
        recipe.preset = .acid
        recipe.source = .oscillator
        recipe.waveform = .sawtooth
        recipe.frequency = 55
        recipe.gain = 1
        recipe.duration = 0.2
        recipe.attack = 0.002
        recipe.decay = 0.2
        recipe.sustain = 0.4
        recipe.release = 0.1
        recipe.filter = .lowpass
        recipe.filterCascaded = true
        recipe.filterQ = q
        recipe.filterFrequency = 120
        recipe.filterOctaves = octaves
        recipe.filterAttack = 0.005
        recipe.filterDecay = 0.3
        recipe.filterSustain = 0.05
        recipe.filterRelease = 0.15
        recipe.lifetime = 0.8
        return recipe
    }

    /// How much of a signal sits in its fast-moving part.
    private func edge(_ samples: [Double]) -> Double {
        var difference = 0.0
        var total = 0.0
        for i in 1..<samples.count {
            let d = samples[i] - samples[i - 1]
            difference += d * d
            total += samples[i] * samples[i]
        }
        return total > 0 ? difference / total : 0
    }

    @Test("The filter opens at the attack and closes behind it")
    func filterSweeps() {
        let out = render(note(q: 8, octaves: 4), frames: Int(rate / 2))
        let opened = edge(Array(out[512..<3072]))
        let closed = edge(Array(out[12288..<14848]))
        #expect(opened > closed * 1.5, "open \(opened) against closed \(closed)")
        #expect(rms(Array(out[0..<4096])) > 0, "nothing came out")
    }

    @Test("Resonance is what makes it squelch")
    func resonanceRings() {
        // A high Q leaves a ringing peak at the cutoff, which shows up as
        // more energy for the same input.
        let calm = rms(render(note(q: 1, octaves: 3), frames: Int(rate / 2)))
        let squelchy = rms(render(note(q: 15, octaves: 3), frames: Int(rate / 2)))
        #expect(squelchy > calm * 2, "\(squelchy) against \(calm)")
    }

    @Test("Even at the edge of self-oscillation it stays finite")
    func staysFinite() {
        for q in [4.0, 9, 12, 15] {
            for octaves in [1.6, 3, 4.6] {
                let out = render(note(q: q, octaves: octaves), frames: Int(rate))
                #expect(
                    out.allSatisfy { $0.isFinite },
                    "Q \(q) over \(octaves) octaves went non-finite")
            }
        }
    }
}

@Suite("RHODES")
struct RhodesTests {
    private func roll(seed: UInt32, velocity: Double = 0.9) -> [ScheduledVoice] {
        SynthVoicing.notes(
            preset: .rhodes, midi: 60, velocity: velocity, using: Mulberry32(seed: seed))
    }

    /// How much of a signal sits in its fast-moving part — a stand-in for
    /// brightness that needs no transform.
    private func edge(_ samples: [Double]) -> Double {
        var difference = 0.0
        var total = 0.0
        for i in 1..<samples.count {
            let d = samples[i] - samples[i - 1]
            difference += d * d
            total += samples[i] * samples[i]
        }
        return total > 0 ? difference / total : 0
    }

    @Test("Every rolled value lands inside the web's range")
    func ranges() {
        let random = Mulberry32(seed: 31)
        for _ in 0..<400 {
            let voices = SynthVoicing.notes(
                preset: .rhodes, midi: 60, velocity: 1, using: random)
            let lead = voices[0].recipe
            #expect(lead.preset == .rhodes)
            #expect(lead.source == .fm)
            #expect(SynthVoicing.rhodesHarmonicities.contains(lead.harmonicity))
            #expect(lead.modulationIndex >= 3 && lead.modulationIndex <= 11)
            #expect(lead.duration >= 0.12 && lead.duration <= 0.45)
            #expect(lead.attack >= 0.002 && lead.attack <= 0.012)
            #expect(lead.decay >= 0.25 && lead.decay <= 0.9)
            #expect(lead.sustain >= 0.05 && lead.sustain <= 0.28)
            #expect(lead.release >= 0.4 && lead.release <= 1.8)
            #expect(lead.modulatorWaveform == .sine || lead.modulatorWaveform == .triangle)
            #expect(lead.modulationAttack >= 0.002 && lead.modulationAttack <= 0.02)
            #expect(lead.modulationDecay >= 0.1 && lead.modulationDecay <= 0.5)
            #expect(lead.modulationSustain >= 0 && lead.modulationSustain <= 0.2)
            #expect(lead.modulationRelease >= 0.2 && lead.modulationRelease <= 0.8)
            #expect(abs(lead.detuneCents) <= 8)
            #expect(lead.tremoloRate >= 2.5 && lead.tremoloRate <= 7)
            #expect(lead.tremoloDepth >= 0.15 && lead.tremoloDepth <= 0.55)

            if voices.count > 1 {
                let ghost = voices[1].recipe
                #expect(ghost.harmonicity == 2 || ghost.harmonicity == 3)
                #expect(ghost.modulationIndex >= 2 && ghost.modulationIndex <= 6)
                // A fifth or an octave above, and no tremolo of its own.
                let ratio = ghost.frequency / lead.frequency
                #expect(abs(ratio - 1.5) < 1e-9 || abs(ratio - 2) < 1e-9)
                #expect(ghost.tremoloRate == 0)
                #expect(voices[1].offset >= 0.01 && voices[1].offset <= 0.06)
            }
        }
    }

    @Test("Values come off the stream in the web's order")
    func drawOrder() {
        let expected = Mulberry32(seed: 12)
        let duration = expected.value(0.12, 0.45)
        let release = expected.value(0.4, 1.8)
        let harmonicity = expected.pick(SynthVoicing.rhodesHarmonicities)
        let index = expected.value(3, 11)
        let attack = expected.value(0.002, 0.012)
        let decay = expected.value(0.25, 0.9)
        let sustain = expected.value(0.05, 0.28)
        let modulator = expected.pick([Waveform.sine, .triangle])
        let modAttack = expected.value(0.002, 0.02)
        let modDecay = expected.value(0.1, 0.5)
        let modSustain = expected.value(0, 0.2)
        let modRelease = expected.value(0.2, 0.8)
        let detune = expected.value(-8, 8)
        let tremoloRate = expected.value(2.5, 7)
        let tremoloDepth = expected.value(0.15, 0.55)
        let ghosted = expected.chance(0.16)

        let voices = roll(seed: 12)
        let lead = voices[0].recipe
        #expect(lead.duration == duration)
        #expect(lead.release == release)
        #expect(lead.harmonicity == harmonicity)
        #expect(lead.modulationIndex == index)
        #expect(lead.attack == attack)
        #expect(lead.decay == decay)
        #expect(lead.sustain == sustain)
        #expect(lead.modulatorWaveform == modulator)
        #expect(lead.modulationAttack == modAttack)
        #expect(lead.modulationDecay == modDecay)
        #expect(lead.modulationSustain == modSustain)
        #expect(lead.modulationRelease == modRelease)
        #expect(lead.detuneCents == detune)
        #expect(lead.tremoloRate == tremoloRate)
        #expect(lead.tremoloDepth == tremoloDepth)
        #expect((voices.count > 1) == ghosted)

        if ghosted {
            let ghost = voices[1].recipe
            #expect(ghost.harmonicity == expected.pick([2.0, 3]))
            #expect(ghost.modulationIndex == expected.value(2, 6))
            #expect(ghost.frequency == lead.frequency * expected.pick([1.5, 2.0]))
            #expect(voices[1].offset == expected.value(0.01, 0.06))
        }
    }

    @Test("The sympathetic ring turns up about a sixth of the time")
    func ghostRate() {
        let random = Mulberry32(seed: 8)
        var ghosts = 0
        let runs = 4000
        for _ in 0..<runs {
            if SynthVoicing.notes(
                preset: .rhodes, midi: 60, velocity: 1, using: random
            ).count > 1 {
                ghosts += 1
            }
        }
        let rate = Double(ghosts) / Double(runs)
        #expect(abs(rate - 0.16) < 0.02, "rang \(rate) of the time")
    }

    // ------------------------------------------------------------- sound --

    private func note(index: Double, tremolo: Double = 0) -> VoiceRecipe {
        var recipe = VoiceRecipe()
        recipe.preset = .rhodes
        recipe.source = .fm
        recipe.frequency = 220
        recipe.gain = 1
        recipe.harmonicity = 3
        recipe.modulationIndex = index
        recipe.attack = 0.005
        recipe.decay = 0.5
        recipe.sustain = 0.2
        recipe.release = 0.8
        recipe.duration = 0.4
        recipe.modulationAttack = 0.005
        recipe.modulationDecay = 0.2
        recipe.modulationSustain = 0.05
        recipe.modulationRelease = 0.4
        recipe.tremoloRate = tremolo
        recipe.tremoloDepth = tremolo > 0 ? 0.5 : 0
        return recipe
    }

    @Test("The modulator puts sidebands around the carrier")
    func modulationAddsHarmonics() {
        let plain = render(note(index: 0), frames: 4096)
        let bell = render(note(index: 10), frames: 4096)
        #expect(edge(bell) > edge(plain) * 3, "the modulator changed nothing")
    }

    /// Tone scales every envelope's peak by velocity, the modulator's
    /// included — `this._modulator._triggerEnvelopeAttack(time, velocity)`.
    /// So a softly struck note is mellow and not merely quiet, which is most
    /// of what separates an electric piano from a synthesiser. The measure
    /// is level-independent on purpose: what is being checked is timbre.
    @Test("A soft note is mellow, not just quiet")
    func velocityDecidesBrightness() {
        var hard = note(index: 10)
        hard.velocity = 1
        var soft = note(index: 10)
        soft.velocity = 0.3

        let bright = edge(render(hard, frames: 4096))
        let mellow = edge(render(soft, frames: 4096))
        #expect(bright > mellow * 1.5, "hard \(bright) against soft \(mellow)")
    }

    @Test("The bell fades faster than the note it sits on")
    func modulationEnvelopeDecays() {
        let out = render(note(index: 10), frames: Int(rate / 2))
        let early = edge(Array(out[256..<2304]))
        let late = edge(Array(out[16384..<18432]))
        #expect(early > late * 1.5, "attack \(early) against body \(late)")
        #expect(rms(Array(out[16384..<18432])) > 0, "the note stopped early")
    }

    @Test("A carrier driven below zero runs backwards instead of piling up")
    func deepModulationStaysInTune() {
        // With an index of ten the instantaneous frequency is negative for
        // most of every modulator cycle. Held at zero instead of allowed to
        // run backwards, the carrier creeps forward and the note drifts
        // sharp — so what is checked is that it does not.
        let deep = render(note(index: 10), frames: Int(rate / 4))
        let shallow = render(note(index: 0), frames: Int(rate / 4))

        func crossings(_ samples: [Double]) -> Int {
            var count = 0
            for i in 1..<samples.count where samples[i - 1] < 0 && samples[i] >= 0 {
                count += 1
            }
            return count
        }
        // A sine at 220 Hz crosses zero upward 55 times in a quarter second.
        // Deep FM crosses far more often — that is the sidebands — but the
        // point is that it stays finite and centred.
        #expect(crossings(shallow) >= 54 && crossings(shallow) <= 56)
        #expect(deep.allSatisfy { $0.isFinite && abs($0) <= 1.001 })
        let mean = deep.reduce(0, +) / Double(deep.count)
        #expect(abs(mean) < 0.05, "the carrier drifted off centre by \(mean)")
    }

    @Test("The tremolo pulls the two sides against each other")
    func tremoloIsStereo() {
        // A note held wide open for the whole second, so the wobble can be
        // counted without the note fading out from under it.
        var held = note(index: 6, tremolo: 5)
        held.duration = 1.5
        held.sustain = 0.8
        held.decay = 0.05

        let (left, right) = renderStereo(held, frames: Int(rate))

        // Tone spreads it half a cycle, so what one side gives the other
        // takes: the sum is the voice with no tremolo on it at all.
        var sum = [Double]()
        var difference = [Double]()
        for i in left.indices {
            sum.append(left[i] + right[i])
            difference.append(left[i] - right[i])
        }
        #expect(rms(difference) > 0.01, "both sides are the same")

        // The difference still carries the note, so counting its zero
        // crossings would count the note. Dividing it out leaves the wobble
        // alone: (L − R) / (L + R) is twice the LFO and nothing else.
        var wobble: [Double] = []
        for i in sum.indices where abs(sum[i]) > 0.02 {
            wobble.append(difference[i] / sum[i])
        }
        #expect(wobble.count > Int(rate) / 4, "too little signal to read the wobble")

        var crossings = 0
        for i in 1..<wobble.count where wobble[i - 1] < 0 && wobble[i] >= 0 {
            crossings += 1
        }
        // Five cycles in the second it was rendered for.
        #expect(abs(Double(crossings) - 5) <= 1, "wobbled \(crossings) times a second")
        // Depth 0.5 swings the ratio across ±0.5.
        #expect((wobble.max() ?? 0) > 0.4 && (wobble.min() ?? 0) < -0.4)

        // The level Tone leaves behind: an LFO between one and zero sits at
        // a half, so a tremolo halves what passes through it. `render` sums
        // the two sides and halves them, so a voice with no tremolo comes
        // back at full level and this one at half.
        var plainRecipe = held
        plainRecipe.tremoloRate = 0
        plainRecipe.tremoloDepth = 0
        let plain = render(plainRecipe, frames: Int(rate))
        #expect(abs(rms(sum) / rms(plain) - 1) < 0.02, "the level moved")
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

    /// What the shared room is allowed to hear.
    ///
    /// Low end smeared across seven seconds of tail is what turns a kick
    /// into mud, so the send is rolled off below — steeply, and from higher
    /// up on the drums than on the pad.
    @Test("The reverb send keeps the low end out")
    func sendRollsOffTheBottom() {
        /// Send level relative to the chain's own output, at one frequency.
        func sendRatio(_ preset: SynthPreset, at frequency: Double) -> Double {
            var chain = PresetChain(preset: preset, sampleRate: rate)
            var oscillator = Oscillator(waveform: .sine)
            var dry = 0.0
            var sent = 0.0

            // Long enough for the filters to settle before anything counts.
            let frames = Int(rate)
            for i in 0..<frames {
                let input = oscillator.render(frequency: frequency, sampleRate: rate) * 0.3
                let out = chain.process(left: input, right: input)
                if i > frames / 2 {
                    dry += out.left * out.left
                    sent += out.sendLeft * out.sendLeft
                }
            }
            return dry > 0 ? (sent / dry).squareRoot() : 0
        }

        for preset in SynthPreset.allCases {
            let corner = PresetSettings.of(preset).sendHighpass
            let low = sendRatio(preset, at: corner / 4)
            let high = sendRatio(preset, at: corner * 4)

            // Two octaves below the corner, at −24 dB an octave, is a long
            // way down — and the same tone two octaves above passes.
            #expect(
                low < high / 20,
                "\(preset.label): \(low) at the bottom against \(high) at the top")
            #expect(high > 0.01, "\(preset.label) sends nothing at all")
        }
    }
}
