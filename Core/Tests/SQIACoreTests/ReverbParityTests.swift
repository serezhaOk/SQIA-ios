// The room, against the room it is standing in for.
//
// This is risk R3 from the plan, measured. The web convolves with a noise
// burst it generates; this is a feedback delay network. The two cannot be
// sample-identical and were never going to be, so what has to match is what
// an ear actually hears from a reverb: how long the tail is, and whether it
// is even across the spectrum.
//
// The finding that made this worth writing: Tone's `decay` is not a decay
// time. `Reverb.rt60(forToneDecay:)` carries the arithmetic, and the web's
// `decay: 7` turns out to be a 2.7-second room. Before this was measured,
// `Tuning.web` held a 7 and the network read it as seven seconds of RT60 —
// a baseline that rang two and a half times longer than the thing it was
// the baseline for.

import Foundation
import Testing

@testable import SQIACore

private let sampleRate = 48000.0

/// Where an impulse through the reverb has fallen 60 dB, in seconds.
///
/// Measured off the energy envelope rather than the raw samples: a tail is
/// noise, and single samples in noise cross any threshold early.
private func measuredRT60(
    decay: Double, damping: Double = 20000, seconds: Double = 8
) -> Double {
    var reverb = Reverb(
        decay: decay, preDelay: 0.001, damping: damping, sampleRate: sampleRate)
    let frames = Int(seconds * sampleRate)
    let window = Int(0.02 * sampleRate)

    var envelope: [Double] = []
    var sum = 0.0
    var counted = 0
    for i in 0..<frames {
        let input = i == 0 ? 1.0 : 0.0
        let (left, right) = reverb.process(left: input, right: input)
        let value = (left * left + right * right) / 2
        sum += value
        counted += 1
        if counted == window {
            envelope.append(sqrt(sum / Double(window)))
            sum = 0
            counted = 0
        }
    }

    // From the peak, not from zero. The tail does not arrive until the
    // impulse has been round the shortest line — about 30 ms — so the first
    // window is silence, and a search that started there would find its own
    // starting gun and call it a 0-second room.
    guard let peak = envelope.max(), peak > 0,
        let peakAt = envelope.firstIndex(of: peak)
    else { return 0 }
    let floor = peak * 0.001  // −60 dB
    for index in peakAt..<envelope.count where envelope[index] < floor {
        return Double(index - peakAt) * 0.02
    }
    return seconds
}

@Suite("The room against the web's")
struct ReverbParityTests {
    @Test("Tone's decay parameter is a time constant, not a decay time")
    func toneDecayIsNotSeconds() {
        // ln(8)/ln(200) · ln(1000), which is the arithmetic in Param.ts
        // followed through. The web asks for 7 and gets 2.7.
        #expect(abs(Reverb.rt60(forToneDecay: 7) - 2.711) < 0.005)
        #expect(abs(Reverb.rt60(forToneDecay: 2.92) - 1.781) < 0.005)
        // Monotonic, and nowhere near the identity anybody would assume.
        #expect(Reverb.rt60(forToneDecay: 1) < Reverb.rt60(forToneDecay: 4))
        #expect(Reverb.rt60(forToneDecay: 7) < 7 / 2)
    }

    @Test("The network's tail is the length it was asked for")
    func decayLawHolds() {
        // Undamped, so this is the feedback gain on its own: 60 dB over the
        // decay, which is what `feedbackGain` is solved for.
        for asked in [1.0, 2.0, 4.0] {
            let measured = measuredRT60(decay: asked)
            #expect(
                abs(measured - asked) < asked * 0.2,
                "asked \(asked)s, measured \(measured)s")
        }
    }

    @Test("The baseline rings for as long as the web's room does")
    func baselineMatchesTheWeb() {
        // This is the A/B. `Tuning.web` is what the parity work is measured
        // against, so its room has to be the web's room — and the web's
        // room is 2.7 seconds however plainly its source says seven.
        let baseline = Tuning.web[.reverbDecay].lower
        let web = Reverb.rt60(forToneDecay: 7)
        #expect(
            abs(baseline - web) < 0.05,
            "the parity baseline is a \(baseline)s room; the web's is \(web)s")

        let measured = measuredRT60(
            decay: baseline, damping: Tuning.web[.reverbDamping].lower)
        // Within a fifth. Two different reverbs will not agree closer than
        // that, and an ear does not hear closer than that either.
        #expect(
            abs(measured - web) < web * 0.2,
            "network measured \(measured)s against the web's \(web)s")
    }

    @Test("The baseline is as bright as the web's, which has no damping at all")
    func baselineIsNotDarkened() {
        // Tone's impulse response is white noise shaped only by a gain
        // envelope — flat, with nothing taken off the top. A damped
        // baseline would make every A/B read as "iOS is duller", which
        // would be true and would be about the baseline rather than about
        // anything either version does.
        let damping = Tuning.web[.reverbDamping].lower
        #expect(
            damping >= 18000,
            "the parity baseline damps at \(damping) Hz; the web damps nowhere")
    }

    @Test("The tuned room is about the web's length, and darker")
    func tunedIsDeliberatelyDifferent() {
        // Worth stating because the plan said the opposite. "Half as long
        // and brighter" was written when a 7 was being read as seven
        // seconds; against the web's real 2.7 the room tuned by ear is
        // almost exactly the same length — 2.92 — and the deliberate
        // difference is the damping, which the web does not have at all.
        //
        // So the ear picked a length within eight per cent of the web's
        // without being told what the web's was, which is a better result
        // than the plan claimed and for a different reason.
        let tuned = Tuning.tuned[.reverbDecay].lower
        let web = Reverb.rt60(forToneDecay: 7)
        #expect(abs(tuned - web) < web * 0.15, "tuned \(tuned)s against \(web)s")

        let tunedDamping = Tuning.tuned[.reverbDamping].lower
        #expect(
            tunedDamping < Tuning.web[.reverbDamping].lower,
            "the room tuned by ear was meant to be the darker one")
    }
}
