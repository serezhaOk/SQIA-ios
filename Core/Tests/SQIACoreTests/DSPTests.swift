// The signal path, checked off a device.
//
// Putting the DSP in the core rather than in AudioUnits is what makes this
// possible: a filter's response, a delay's spacing and a limiter's curve are
// all things a test can assert on, instead of things somebody has to listen
// for.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

@Suite("Biquad")
struct BiquadTests {
    @Test("A lowpass passes DC and stops the top end")
    func lowpassResponse() {
        let filter = Biquad(lowpass: 2400, sampleRate: rate)
        #expect(abs(filter.magnitude(at: 0, sampleRate: rate) - 1) < 1e-9)
        // An octave up is already down; four octaves up is gone.
        #expect(filter.magnitude(at: 4800, sampleRate: rate) < 0.35)
        #expect(filter.magnitude(at: 19_200, sampleRate: rate) < 0.01)
    }

    @Test("The response falls monotonically above the corner")
    func monotone() {
        let filter = Biquad(lowpass: 2400, sampleRate: rate)
        var previous = Double.infinity
        for f in stride(from: 3000.0, to: 20_000.0, by: 250) {
            let m = filter.magnitude(at: f, sampleRate: rate)
            #expect(m < previous)
            previous = m
        }
    }

    @Test("It is stable: an impulse dies away")
    func stability() {
        var filter = Biquad(lowpass: 2400, sampleRate: rate)
        var peak = 0.0
        var last = 0.0
        for i in 0..<10_000 {
            last = filter.process(i == 0 ? 1 : 0)
            peak = max(peak, abs(last))
        }
        #expect(peak < 10)
        #expect(abs(last) < 1e-9)
    }

    @Test("Absurd frequencies are clamped rather than exploding")
    func clamping() {
        for f in [-100.0, 0, 1e9] {
            var filter = Biquad(lowpass: f, sampleRate: rate)
            for _ in 0..<1000 { _ = filter.process(1) }
            #expect(filter.process(1).isFinite)
        }
    }
}

@Suite("Delay line")
struct DelayLineTests {
    @Test("An impulse comes back out after exactly the delay")
    func spacing() {
        var line = DelayLine(maximum: 1, delay: 0.01, sampleRate: rate)  // 480 frames
        var onset = -1
        for i in 0..<2000 {
            let out = line.process(i == 0 ? 1 : 0)
            if out != 0 && onset < 0 { onset = i }
        }
        #expect(onset == 480)
    }

    @Test("Clearing empties the line")
    func clearing() {
        var line = DelayLine(maximum: 1, delay: 0.01, sampleRate: rate)
        for _ in 0..<100 { _ = line.process(1) }
        line.clear()
        for _ in 0..<480 { #expect(line.process(0) == 0) }
    }
}

@Suite("Slap delay")
struct SlapDelayTests {
    @Test("Echoes land 170 ms apart and get quieter")
    func echoes() {
        var slap = SlapDelay(sampleRate: rate)
        var peaks: [(frame: Int, value: Double)] = []
        var window: (frame: Int, value: Double) = (0, 0)

        for i in 0..<Int(rate * 0.8) {
            let out = abs(slap.process(left: i == 0 ? 1 : 0, right: 0).left)
            if out > window.value { window = (i, out) }
            // Close off a window every 170 ms and keep its peak.
            if i % Int(rate * SlapDelay.delayTime) == Int(rate * SlapDelay.delayTime) - 1 {
                if window.value > 1e-6 { peaks.append(window) }
                window = (0, 0)
            }
        }

        #expect(peaks.count >= 3)
        for (a, b) in zip(peaks, peaks.dropFirst()) {
            let spacing = Double(b.frame - a.frame) / rate
            #expect(abs(spacing - SlapDelay.delayTime) < 0.02)
            #expect(b.value < a.value)  // feedback below unity, so it decays
        }
    }

    @Test("The send is quiet: the first echo is a fraction of the input")
    func sendLevel() {
        var slap = SlapDelay(sampleRate: rate)
        var loudest = 0.0
        for i in 0..<Int(rate * 0.25) {
            loudest = max(loudest, abs(slap.process(left: i == 0 ? 1 : 0, right: 0).left))
        }
        #expect(loudest < SlapDelay.sendGain)
    }

    @Test("The feedback loop settles instead of running away")
    func converges() {
        var slap = SlapDelay(sampleRate: rate)
        var late = 0.0
        for i in 0..<Int(rate * 12) {
            let out = slap.process(left: i == 0 ? 1 : 0, right: 0).left
            if i > Int(rate * 10) { late = max(late, abs(out)) }
        }
        #expect(late < 1e-6)
    }
}

@Suite("Limiter")
struct LimiterTests {
    @Test("Quiet signals pass untouched")
    func belowKnee() {
        // The knee opens 15 dB below the threshold, so anything under −23 dB
        // is not compressed at all.
        #expect(Limiter.gainReduction(forLevel: -40) == 0)
        #expect(Limiter.gainReduction(forLevel: -24) == 0)
    }

    @Test("Loud signals are pulled toward the threshold")
    func aboveKnee() {
        // The knee is 30 dB wide, so the full ratio only applies from
        // −8 + 15 = +7 dB up. At +12 dB, 12:1 puts the output at
        // −8 + 20/12 ≈ −6.33 dB.
        let output = 12 + Limiter.gainReduction(forLevel: 12)
        #expect(abs(output - (-8 + 20 / 12.0)) < 1e-9)
        // Getting louder still buys almost nothing: 12 dB more in, 1 dB out.
        let louder = 24 + Limiter.gainReduction(forLevel: 24)
        #expect(abs((louder - output) - 1) < 1e-9)
    }

    /// What a soft knee is: the ratio arrives gradually rather than
    /// switching on. It starts compressing a little below the threshold and
    /// reaches the full 12:1 at the top of the knee, and the slope of the
    /// input/output curve is where that shows.
    @Test("Across the knee the ratio climbs from 1:1 to the full ratio")
    func kneeSlope() {
        func slope(at dB: Double) -> Double {
            let h = 1e-4
            let low = dB - h + Limiter.gainReduction(forLevel: dB - h)
            let high = dB + h + Limiter.gainReduction(forLevel: dB + h)
            return (high - low) / (2 * h)
        }

        let kneeStart = Limiter.threshold - Limiter.knee / 2  // −23 dB
        let kneeEnd = Limiter.threshold + Limiter.knee / 2  // +7 dB

        #expect(abs(slope(at: kneeStart - 5) - 1) < 1e-6)  // untouched
        #expect(abs(slope(at: kneeEnd + 5) - 1 / Limiter.ratio) < 1e-6)  // full ratio

        // And in between it only ever tightens.
        var previous = 1.0
        for dB in stride(from: kneeStart, through: kneeEnd, by: 1) {
            let s = slope(at: dB)
            #expect(s <= previous + 1e-6)
            #expect(s >= 1 / Limiter.ratio - 1e-6)
            previous = s
        }
    }

    @Test("The knee is smooth, not a corner")
    func kneeIsContinuous() {
        var previous = 0.0
        for dB in stride(from: -40.0, through: 12.0, by: 0.25) {
            let reduction = Limiter.gainReduction(forLevel: dB)
            #expect(reduction <= 1e-12)  // never boosts
            #expect(reduction <= previous + 1e-9)  // never eases off as it gets louder
            #expect(abs(reduction - previous) < 0.5)  // no jump
            previous = reduction
        }
    }

    @Test("A sustained loud tone is brought down")
    func holdsLoudMaterial() {
        var limiter = Limiter(sampleRate: rate)
        var peak = 0.0
        // A second of full-scale sine, measured after the envelope settles.
        for i in 0..<Int(rate) {
            let x = sin(2 * Double.pi * 220 * Double(i) / rate)
            let out = limiter.process(left: x, right: x)
            if i > Int(rate / 2) { peak = max(peak, abs(out.left)) }
        }
        // −8 dB is 0.398; the knee lets a little through above that.
        #expect(peak < 0.65)
        #expect(peak > 0.2)
    }

    @Test("It gets out of the way again")
    func releases() {
        var limiter = Limiter(sampleRate: rate)
        for i in 0..<Int(rate / 2) {
            let x = sin(2 * Double.pi * 220 * Double(i) / rate)
            _ = limiter.process(left: x, right: x)
        }
        // Drop to a quiet tone and let the release run well past 180 ms.
        var peak = 0.0
        for i in 0..<Int(rate) {
            let x = 0.05 * sin(2 * Double.pi * 220 * Double(i) / rate)
            let out = limiter.process(left: x, right: x)
            if i > Int(rate / 2) { peak = max(peak, abs(out.left)) }
        }
        #expect(peak > 0.045)  // back to roughly unity
    }

    @Test("Silence in, silence out")
    func silence() {
        var limiter = Limiter(sampleRate: rate)
        for _ in 0..<1000 {
            let out = limiter.process(left: 0, right: 0)
            #expect(out.left == 0 && out.right == 0)
        }
    }
}

@Suite("Sample envelope")
struct SampleEnvelopeTests {
    @Test("It starts silent, rises over 6 ms, then falls to the floor")
    func shape() {
        let envelope = SampleEnvelope(peak: 0.8, release: 0.4)
        #expect(envelope.value(at: 0) == 0)
        #expect(abs(envelope.value(at: SampleEnvelope.attack / 2) - 0.4) < 1e-9)
        #expect(abs(envelope.value(at: SampleEnvelope.attack) - 0.8) < 1e-9)
        #expect(envelope.value(at: 0.2) < 0.8)
        #expect(abs(envelope.value(at: 0.4) - SampleEnvelope.floor) < 1e-9)
        #expect(envelope.value(at: 10) == SampleEnvelope.floor)
    }

    @Test("The fall never turns back up")
    func monotoneDecay() {
        let envelope = SampleEnvelope(peak: 1, release: 0.5)
        var previous = 1.0
        for t in stride(from: SampleEnvelope.attack, through: 0.5, by: 0.001) {
            let v = envelope.value(at: t)
            #expect(v <= previous + 1e-12)
            previous = v
        }
    }

    @Test("A hit rings for as long as it sounds, within limits")
    func releaseLength() {
        // A one-second sample at natural pitch, tail scaled to 50%.
        #expect(abs(SampleEnvelope.release(bufferDuration: 1, rate: 1, scale: 0.5) - 0.5) < 1e-12)
        // Played an octave up it is over twice as fast.
        #expect(abs(SampleEnvelope.release(bufferDuration: 1, rate: 2, scale: 1) - 0.5) < 1e-12)
        // Long samples are capped at 1.5 s before scaling.
        #expect(abs(SampleEnvelope.release(bufferDuration: 30, rate: 1, scale: 1) - 1.5) < 1e-12)
        // And nothing is shorter than 80 ms.
        #expect(SampleEnvelope.release(bufferDuration: 0.01, rate: 4, scale: 0.1) == 0.08)
    }
}
