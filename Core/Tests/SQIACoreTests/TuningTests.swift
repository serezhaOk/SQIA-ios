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

        #expect(web[.reverbDecay] == TunableRange(7))
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
        var tuning = Tuning.web
        #expect(tuning.isWeb)
        #expect(tuning.changes().isEmpty)

        tuning[.rhodesTremoloDepth] = TunableRange(0, 0.9)
        let changes = tuning.changes()
        #expect(changes.count == 1)
        #expect(changes[0].spec.knob == .rhodesTremoloDepth)
        #expect(changes[0].from == TunableRange(0.15, 0.55))
        #expect(changes[0].to == TunableRange(0, 0.9))

        tuning.reset(.rhodesTremoloDepth)
        #expect(tuning.isWeb)
    }
}
