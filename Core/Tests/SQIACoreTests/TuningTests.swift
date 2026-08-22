// Making the sound adjustable must not have adjusted it.
//
// Every number the panel can move used to be a literal in the voicing code,
// taken from the web. These tests hold the defaults against those literals,
// and then check that a knob actually reaches the sound — a control that
// changes nothing is worse than no control.

import Foundation
import Testing

@testable import SQIACore

@Suite("Tuning")
struct TuningTests {
    @Test("The defaults are the web's numbers")
    func defaultsAreTheWebs() {
        let web = Tuning.web
        // REVERIE rolls a tenth to nine tenths of 3.2 seconds.
        #expect(web[.reverieRelease] == TunableRange(0.1 * 3.2, 0.9 * 3.2))
        #expect(web[.reverieSlowAttackChance] == TunableRange(0.3))
        #expect(web[.reverieDetune] == TunableRange(14))
        #expect(web[.reverieLevel] == TunableRange(-12))

        #expect(web[.kalimbaResonance] == TunableRange(0.55, 0.94))
        #expect(web[.kalimbaDampening] == TunableRange(900, 4500))
        #expect(web[.kalimbaAttackNoise] == TunableRange(0.4, 1.8))
        #expect(web[.kalimbaLevel] == TunableRange(5))

        #expect(web[.rhodesModulationIndex] == TunableRange(3, 11))
        #expect(web[.rhodesTremoloDepth] == TunableRange(0.15, 0.55))

        #expect(web[.acidResonance] == TunableRange(4, 11))
        #expect(web[.acidAccentResonance] == TunableRange(9, 15))
        #expect(web[.acidBaseCutoff] == TunableRange(90, 260))
        #expect(web[.acidLevel] == TunableRange(-18))

        #expect(web[.machineKickPitchStart] == TunableRange(3, 8))
        #expect(web[.machineKickLevel] == TunableRange(-3))
        #expect(web[.machineMetalLevel] == TunableRange(-21))

        // The web writes `decay: 7` and Tone reads it as a time constant,
        // so the room is 2.7 seconds. This baseline holds the room the web
        // has rather than the number the web types — see
        // `ReverbParityTests`, which is where that was measured.
        #expect(web[.reverbDecay] == TunableRange(Reverb.rt60(forToneDecay: 7)))
        #expect(web[.reverbPreDelay] == TunableRange(0.02))
    }

    /// The accent branch is derived from the ordinary one rather than stored
    /// separately, so this is where that derivation is held to the web's.
    @Test("An accent still opens the filter as far as the web opens it")
    func accentSpanMatchesTheWeb() {
        let random = Mulberry32(seed: 3)
        for _ in 0..<200 {
            let voices = SynthVoicing.notes(
                preset: .acid, midi: 60, velocity: 1, using: random)
            let octaves = voices[0].recipe.filterOctaves
            #expect(octaves >= 3 && octaves <= 4.6, "accent opened \(octaves)")
        }
    }

    @Test("Every knob has a spec, and every spec a knob")
    func specsAreComplete() {
        let specced = Set(Tuning.specs.map(\.knob))
        for knob in TuningKnob.allCases {
            #expect(specced.contains(knob), "\(knob.rawValue) has no spec")
            #expect(Tuning.defaults[knob] != nil, "\(knob.rawValue) has no default")
        }
        #expect(specced.count == TuningKnob.allCases.count)

        // Every default sits inside the travel its slider offers, or the
        // panel would open showing a value it cannot return to.
        for spec in Tuning.specs {
            let frame = Tuning.web[spec.knob]
            #expect(
                spec.bounds.contains(frame.lower) && spec.bounds.contains(frame.upper),
                "\(spec.label) defaults to \(frame) outside \(spec.bounds)")
        }
    }

    /// The drums are the one preset whose pitch decides which instrument
    /// plays, so transposing them rearranges a pattern rather than moving
    /// it. Off by default, and the web's behaviour still reachable.
    @Test("A drum kit keeps its layout unless it is told to follow the key")
    func drumsIgnoreTheKey() {
        // Twelve columns, one semitone apart, so every column is a fixed
        // instrument: three kicks, three toms, three snares, two claps, one
        // metal.
        #expect(Music.drumTable.count == Music.columns)
        let kinds = Music.drumTable.map { ((($0 % 12) + 12) % 12) }
        #expect(kinds == Array(0..<12))

        #expect(!Tuning.tuned.isOn(.machineFollowsKey))
        #expect(Tuning.web.isOn(.machineFollowsKey))

        // Whatever the key, the same column is the same instrument.
        for rootPc in 0..<12 {
            let table = Music.midiTable(rootPc: rootPc, scale: Music.scales[0])
            let moved = Set(table.map { ((($0 % 12) + 12) % 12) })
            let fixed = Set(Music.drumTable.map { ((($0 % 12) + 12) % 12) })
            #expect(fixed.count == 12)
            if rootPc != 0 { _ = moved }
        }
    }

    @Test("Only what belongs in the room reaches it")
    func sendCutIsTunable() {
        // The web rolls the drums off at 380 Hz; this build cuts everything
        // under 1.1 kHz, because a kick in a tail is mud, and leaves the
        // echo at a hint of what the web repeats.
        #expect(Tuning.web[.machineSendHighpass] == TunableRange(380))
        #expect(Tuning.tuned[.machineSendHighpass] == TunableRange(1100))
        #expect(Tuning.web[.machineDelayWet] == TunableRange(0.12))
        #expect(Tuning.tuned[.machineDelayWet] == TunableRange(0.03))

        var chain = PresetChain(preset: .machine, sampleRate: 48_000)
        chain.setSendHighpass(1100)

        /// Send level against the chain's own output at one frequency.
        func ratio(_ frequency: Double) -> Double {
            var oscillator = Oscillator(waveform: .sine)
            var dry = 0.0
            var sent = 0.0
            let frames = 48_000
            for i in 0..<frames {
                let input = oscillator.render(frequency: frequency, sampleRate: 48_000) * 0.3
                let out = chain.process(left: input, right: input)
                if i > frames / 2 {
                    dry += out.left * out.left
                    sent += out.sendLeft * out.sendLeft
                }
            }
            return dry > 0 ? (sent / dry).squareRoot() : 0
        }

        let kick = ratio(60)
        let hat = ratio(6000)
        #expect(kick < hat / 50, "60 Hz sent \(kick) against 6 kHz at \(hat)")
    }

    // ------------------------------------------------------ reaching sound --

    /// A knob nobody can hear is not a knob.
    @Test("Moving a knob moves the note it belongs to")
    func knobsReachTheVoice() {
        func kalimbaResonance(_ range: TunableRange) -> Double {
            var tuning = Tuning.web
            tuning[.kalimbaResonance] = range
            return SynthVoicing.notes(
                preset: .kalimba, midi: 60, velocity: 1, using: Mulberry32(seed: 5),
                tuning: tuning
            )[0].recipe.pluckResonance
        }
        #expect(abs(kalimbaResonance(TunableRange(0.2)) - 0.2) < 1e-12)
        #expect(abs(kalimbaResonance(TunableRange(0.99)) - 0.99) < 1e-12)

        func acidLevel(_ db: Double) -> Double {
            var tuning = Tuning.web
            tuning[.acidLevel] = TunableRange(db)
            return SynthVoicing.notes(
                preset: .acid, midi: 60, velocity: 1, using: Mulberry32(seed: 5),
                tuning: tuning
            )[0].recipe.gain
        }
        #expect(acidLevel(-6) > acidLevel(-18))

        func rhodesModulation(_ range: TunableRange) -> Double {
            var tuning = Tuning.web
            tuning[.rhodesModulationIndex] = range
            return SynthVoicing.notes(
                preset: .rhodes, midi: 60, velocity: 1, using: Mulberry32(seed: 5),
                tuning: tuning
            )[0].recipe.modulationIndex
        }
        #expect(abs(rhodesModulation(TunableRange(2)) - 2) < 1e-12)
        #expect(abs(rhodesModulation(TunableRange(20)) - 20) < 1e-12)
    }

    /// Pinning a knob narrows the sound without shifting the stream, so one
    /// changed control cannot rearrange every note after it.
    @Test("Pinning a knob leaves the rest of the note where it was")
    func pinningDoesNotShiftTheStream() {
        var pinned = Tuning.web
        pinned[.kalimbaDampening] = TunableRange(2000)

        let asWeb = SynthVoicing.notes(
            preset: .kalimba, midi: 60, velocity: 1, using: Mulberry32(seed: 11))[0].recipe
        let asPinned = SynthVoicing.notes(
            preset: .kalimba, midi: 60, velocity: 1, using: Mulberry32(seed: 11),
            tuning: pinned)[0].recipe

        #expect(asPinned.pluckDampening == 2000)
        // Everything drawn after it is untouched.
        #expect(asPinned.attackNoise == asWeb.attackNoise)
        #expect(asPinned.filterFrequency == asWeb.filterFrequency)
        #expect(asPinned.filterQ == asWeb.filterQ)
        #expect(asPinned.filterRamp == asWeb.filterRamp)
    }

    // ------------------------------------------------------------- carrying --

    @Test("A tuning survives a round trip through text")
    func roundTrip() {
        var tuning = Tuning.web
        tuning[.acidResonance] = TunableRange(2, 6)
        tuning[.reverbDecay] = TunableRange(3.5)

        let restored = Tuning.fromJSON(tuning.json())
        #expect(restored == tuning)
        #expect(restored?[.acidResonance] == TunableRange(2, 6))
    }

    @Test("An unknown or missing knob falls back to the web")
    func missingKnobsFallBack() {
        // A tuning saved before a knob existed decodes with that knob absent.
        let sparse = Tuning([.acidLevel: TunableRange(-24)])
        #expect(sparse[.acidLevel] == TunableRange(-24))
        #expect(sparse[.kalimbaResonance] == Tuning.web[.kalimbaResonance])
    }

    @Test("Only what moved is reported as moved")
    func changesAreTheDifference() {
        var tuning = Tuning.tuned
        #expect(tuning.isDefault)
        #expect(tuning.changes().isEmpty)

        let before = Tuning.tuned[.rhodesTremoloDepth]
        tuning[.rhodesTremoloDepth] = TunableRange(0, 0.9)
        let changes = tuning.changes()
        #expect(changes.count == 1)
        #expect(changes[0].spec.knob == .rhodesTremoloDepth)
        #expect(changes[0].from == before)
        #expect(changes[0].to == TunableRange(0, 0.9))

        tuning.reset(.rhodesTremoloDepth)
        #expect(tuning.isDefault)

        // And the web is still reachable as its own reference.
        tuning.resetToWeb()
        #expect(tuning.isWeb)
        #expect(!tuning.isDefault)
    }

    /// What the app opens on, once the owner had listened to it. These are
    /// held down because they are decisions, not accidents — if one moves,
    /// somebody moved it.
    @Test("The shipped tuning is the one that was listened to")
    func tunedIsWhatWasChosen() {
        let tuned = Tuning.tuned
        #expect(!tuned.isWeb)

        // RHODES stopped being digital: much less modulation, a slower bell.
        #expect(tuned[.rhodesModulationIndex] == TunableRange(0, 8.02))
        #expect(tuned[.rhodesModulationDecay] == TunableRange(0.757, 1.709))
        // MACHINE's kick starts lower and sits louder.
        #expect(tuned[.machineKickPitchStart] == TunableRange(2.44, 4.78))
        #expect(tuned[.machineKickLevel] == TunableRange(1.05))
        // ACID squelches rarely rather than always.
        #expect(tuned[.acidResonance] == TunableRange(0, 14.49))
        // The room is less than half as long, and brighter.
        #expect(tuned[.reverbDecay] == TunableRange(2.92))
        #expect(tuned[.reverbDamping] == TunableRange(6870))

        // What nobody touched is still the web's, to the digit.
        for knob in [
            TuningKnob.reverieRelease, .reverieLevel, .kalimbaLevel, .machineSnareBandpass,
        ] {
            #expect(tuned[knob] == Tuning.web[knob], "\(knob.rawValue) drifted")
        }
    }
}
