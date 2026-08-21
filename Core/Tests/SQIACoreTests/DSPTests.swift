// The signal path, checked off a device.
//
// Putting the DSP in the core rather than in AudioUnits is what makes this
// possible: a filter's response, an oscillator's spectrum, a limiter's curve
// and a reverb's decay are all things a test can assert on, instead of
// things somebody has to listen for.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

/// Root mean square of a buffer — the honest measure of how loud something
/// is, as against how tall its tallest spike happens to be.
private func rms(_ samples: [Double]) -> Double {
    guard !samples.isEmpty else { return 0 }
    return (samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)).squareRoot()
}

@Suite("Biquad")
struct BiquadTests {
    @Test("A lowpass passes DC and stops the top end")
    func lowpassResponse() {
        let filter = Biquad(lowpass: 2400, sampleRate: rate)
        #expect(abs(filter.magnitude(at: 0, sampleRate: rate) - 1) < 1e-9)
        #expect(filter.magnitude(at: 4800, sampleRate: rate) < 0.35)
        #expect(filter.magnitude(at: 19_200, sampleRate: rate) < 0.01)
    }

    @Test("A highpass does the opposite")
    func highpassResponse() {
        let filter = Biquad(highpass: 2400, sampleRate: rate)
        #expect(filter.magnitude(at: 0, sampleRate: rate) < 1e-6)
        #expect(filter.magnitude(at: 300, sampleRate: rate) < 0.05)
        #expect(filter.magnitude(at: 19_200, sampleRate: rate) > 0.9)
    }

    /// Web Audio reads Q in decibels for a lowpass and a highpass, and as
    /// the quality factor for everything else. It is an easy thing to miss
    /// and an expensive one: the 303's filter is rolled up to fifteen, and
    /// read the wrong way that is a quality factor of fifteen — twenty-three
    /// decibels of resonance where the web has fifteen, doubled again by the
    /// cascade. The bass disappears underneath it.
    @Test("Q is decibels on a lowpass, and a quality factor on a bandpass")
    func resonanceIsInDecibels() {
        for decibels in [1.0, 4, 9, 15] {
            let low = Biquad(lowpass: 2000, q: decibels, sampleRate: rate)
            let peak = low.magnitude(at: 2000, sampleRate: rate)
            #expect(
                abs(20 * log10(peak) - decibels) < 0.6,
                "lowpass at Q \(decibels) peaked at \(20 * log10(peak)) dB")

            let high = Biquad(highpass: 2000, q: decibels, sampleRate: rate)
            let highPeak = high.magnitude(at: 2000, sampleRate: rate)
            #expect(abs(20 * log10(highPeak) - decibels) < 0.6)
        }

        // A bandpass is unchanged: its Q is the quality factor, so its
        // bandwidth narrows with it while the peak stays at unity.
        let narrow = Biquad(bandpass: 2000, q: 8, sampleRate: rate)
        let wide = Biquad(bandpass: 2000, q: 2, sampleRate: rate)
        #expect(abs(narrow.magnitude(at: 2000, sampleRate: rate) - 1) < 0.05)
        #expect(
            narrow.magnitude(at: 2600, sampleRate: rate)
                < wide.magnitude(at: 2600, sampleRate: rate))
    }

    @Test("A bandpass peaks where it is tuned and falls away either side")
    func bandpassResponse() {
        let filter = Biquad(bandpass: 2000, q: 4, sampleRate: rate)
        let peak = filter.magnitude(at: 2000, sampleRate: rate)
        #expect(abs(peak - 1) < 0.05)
        #expect(filter.magnitude(at: 500, sampleRate: rate) < 0.4)
        #expect(filter.magnitude(at: 8000, sampleRate: rate) < 0.4)
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

    @Test("A fractional delay lands between samples")
    func fractional() {
        var line = DelayLine(maximum: 1, delay: 0.01, sampleRate: rate)
        // A ramp in, read back half a sample late: every output should sit
        // midway between two inputs.
        for i in 0..<200 {
            let out = line.process(Double(i), delaySamples: 10.5)
            if i > 20 {
                #expect(abs(out - (Double(i) - 10.5)) < 1e-9, "frame \(i): \(out)")
            }
        }
    }

    @Test("Clearing empties the line")
    func clearing() {
        var line = DelayLine(maximum: 1, delay: 0.01, sampleRate: rate)
        for _ in 0..<100 { _ = line.process(1) }
        line.clear()
        for _ in 0..<480 { #expect(line.process(0) == 0) }
    }
}

@Suite("Oscillator")
struct OscillatorTests {
    private func run(_ waveform: Waveform, frequency: Double, frames: Int) -> [Double] {
        var oscillator = Oscillator(waveform: waveform)
        return (0..<frames).map { _ in
            oscillator.render(frequency: frequency, sampleRate: rate)
        }
    }

    @Test("Every shape stays inside the rails and carries some level")
    func levels() {
        for waveform in Waveform.allCases {
            let out = run(waveform, frequency: 220, frames: 4800)
            #expect(out.allSatisfy { abs($0) <= 1.05 }, "\(waveform) overshot")
            #expect(rms(out) > 0.1, "\(waveform) was too quiet")
        }
    }

    /// A shape whose modulator runs at the carrier's own frequency carries
    /// a constant term — AM because a quarter of its output is a squared
    /// sine, FM because the carrier spends longer at some phases than
    /// others. Both are what Tone produces, and the amplitude envelope takes
    /// the note up from and back down to silence either way, so neither
    /// clicks. The plain shapes have no such excuse.
    @Test("Only the self-modulated shapes carry a standing offset")
    func dcOffset() {
        let selfModulated: Set<Waveform> = [.amSine, .fmSine, .fmTriangle]

        for waveform in Waveform.allCases {
            // A whole number of cycles, so any residue is the shape's own.
            let out = run(waveform, frequency: 100, frames: 4800)
            let mean = out.reduce(0, +) / Double(out.count)

            if selfModulated.contains(waveform) {
                #expect(abs(mean) < 0.3, "\(waveform) sits at \(mean)")
            } else {
                #expect(abs(mean) < 0.06, "\(waveform) sits at \(mean)")
            }
        }
    }

    @Test("A sine is a sine")
    func sineIsExact() {
        let out = run(.sine, frequency: 480, frames: 100)
        for (i, value) in out.enumerated() {
            #expect(abs(value - sin(2 * .pi * 480 * Double(i) / rate)) < 1e-12)
        }
    }

    @Test("It comes back to the same place after a whole number of cycles")
    func periodic() {
        // The fat shapes are three voices detuned against each other, so
        // they are aperiodic on purpose — that beating is the whole point of
        // them. Everything else must land back where it started.
        let steady = Waveform.allCases.filter {
            $0 != .fatSawtooth && $0 != .fatTriangle
        }
        for waveform in steady {
            let out = run(waveform, frequency: 100, frames: 1440)  // three cycles
            let period = Int(rate / 100)
            for i in 0..<period {
                #expect(
                    abs(out[i] - out[i + period]) < 1e-6,
                    "\(waveform) drifted by frame \(i)")
            }
        }
    }

    @Test("The fat shapes beat instead of repeating")
    func fatDrifts() {
        for waveform in [Waveform.fatSawtooth, .fatTriangle] {
            let out = run(waveform, frequency: 100, frames: 1440)
            let period = Int(rate / 100)
            let drift = (0..<period).map { abs(out[$0] - out[$0 + period]) }.max() ?? 0
            #expect(drift > 0.01, "\(waveform) did not drift at all")
        }
    }

    /// A naive sawtooth folds its whole spectrum back on itself. The
    /// band-limited one should be far quieter above Nyquist's reflection.
    @Test("Sawtooth and square are band-limited")
    func bandLimited() {
        // A high note, where aliasing is worst: 5 kHz has only four
        // harmonics below Nyquist.
        for waveform in [Waveform.fatSawtooth, .square] {
            let out = run(waveform, frequency: 5000, frames: 8192)
            // Energy near DC is where alias products pile up; a clean
            // 5 kHz tone should have almost none.
            var low = 0.0
            var filter = Biquad(lowpass: 800, sampleRate: rate)
            for value in out { low += pow(filter.process(value), 2) }
            let ratio = (low / Double(out.count)).squareRoot() / rms(out)
            #expect(ratio < 0.1, "\(waveform) aliased: \(ratio)")
        }
    }

    @Test("Resetting starts the phase over")
    func resetting() {
        var oscillator = Oscillator(waveform: .sine)
        for _ in 0..<100 { _ = oscillator.render(frequency: 440, sampleRate: rate) }
        oscillator.reset()
        #expect(abs(oscillator.render(frequency: 440, sampleRate: rate)) < 1e-12)
    }
}

@Suite("Envelopes")
struct EnvelopeTests {
    @Test("Attack rises, decay falls to sustain, release falls to nothing")
    func shape() {
        var envelope = ADSR(attack: 0.01, decay: 0.05, sustain: 0.4, release: 0.1)
        envelope.trigger(duration: 0.2, sampleRate: rate)

        // Halfway up the attack.
        for _ in 0..<Int(0.005 * rate) { _ = envelope.next() }
        let rising = envelope.next()
        #expect(rising > 0.4 && rising < 0.6)

        // Through the decay, at sustain.
        for _ in 0..<Int(0.07 * rate) { _ = envelope.next() }
        #expect(abs(envelope.next() - 0.4) < 0.01)

        // Past the hold, into the release, and gone.
        for _ in 0..<Int(0.35 * rate) { _ = envelope.next() }
        #expect(envelope.isFinished)
        #expect(envelope.next() == 0)
    }

    @Test("A note lets go of itself when its time is up")
    func selfReleasing() {
        var envelope = ADSR(attack: 0.001, decay: 0.01, sustain: 0.8, release: 0.05)
        envelope.trigger(duration: 0.1, sampleRate: rate)
        var frames = 0
        while !envelope.isFinished && frames < Int(rate) {
            _ = envelope.next()
            frames += 1
        }
        let seconds = Double(frames) / rate
        #expect(abs(seconds - 0.15) < 0.01, "ran for \(seconds)s")
    }

    @Test("A note cut during its attack falls from where it was")
    func releaseFromPartial() {
        var envelope = ADSR(attack: 1, decay: 0.1, sustain: 0.5, release: 0.05)
        envelope.trigger(duration: 10, sampleRate: rate)
        for _ in 0..<Int(0.25 * rate) { _ = envelope.next() }
        let level = envelope.next()
        envelope.releaseNow()
        let first = envelope.next()
        #expect(first <= level)
        #expect(first > level * 0.9)
    }

    /// Tone ramps a membrane's pitch exponentially, which is a constant
    /// ratio per sample — so this steps rather than evaluating a power.
    ///
    /// And it starts at `freq * octaves`, a plain multiply, however much the
    /// parameter's name suggests otherwise: `maxNote = freq * this.octaves`
    /// in MembraneSynth. Read as a power instead, a kick rolled at eight
    /// starts two hundred and fifty-six times above its fundamental rather
    /// than eight, which is a descending zap and not a struck skin.
    @Test("A drum's pitch falls to the note it was given")
    func pitchDrop() {
        var pitch = PitchEnvelope(octaves: 3, decay: 0.05)
        pitch.prepare(sampleRate: rate)
        let start = pitch.next(base: 100)
        #expect(abs(start - 300) < 1, "started at \(start)")

        // A constant ratio per sample: halfway through the decay it has
        // covered half the ratio, which is its square root.
        for _ in 0..<Int(0.025 * rate) { _ = pitch.next(base: 100) }
        let middle = pitch.next(base: 100)
        #expect(abs(middle - 100 * 3.0.squareRoot()) < 5, "midway at \(middle)")

        for _ in 0..<Int(0.05 * rate) { _ = pitch.next(base: 100) }
        #expect(abs(pitch.next(base: 100) - 100) < 1)
    }
}

@Suite("Noise")
struct NoiseTests {
    @Test("White noise is loud, centred and unpredictable")
    func white() {
        var noise = Noise(colour: .white, seed: 12345)
        let out = (0..<48_000).map { _ in noise.next() }
        #expect(out.allSatisfy { abs($0) <= 1 })
        #expect(abs(out.reduce(0, +) / Double(out.count)) < 0.02)
        #expect(rms(out) > 0.4)
    }

    @Test("Pink noise has more weight down low than white does")
    func pink() {
        func lowEnergy(_ colour: NoiseColour) -> Double {
            var noise = Noise(colour: colour, seed: 999)
            var filter = Biquad(lowpass: 400, sampleRate: rate)
            let out = (0..<48_000).map { _ in filter.process(noise.next()) }
            var flat = Noise(colour: colour, seed: 999)
            let whole = (0..<48_000).map { _ in flat.next() }
            return rms(out) / rms(whole)
        }
        #expect(lowEnergy(.pink) > lowEnergy(.white) * 1.5)
    }

    @Test("Different seeds give different noise")
    func seeded() {
        var a = Noise(seed: 1)
        var b = Noise(seed: 2)
        let first = (0..<100).map { _ in a.next() }
        let second = (0..<100).map { _ in b.next() }
        #expect(first != second)
    }
}

@Suite("Effects")
struct EffectsTests {
    @Test("The chorus moves what it passes")
    func chorusModulates() {
        var chorus = Chorus(depth: 0.55, wet: 1, sampleRate: rate)
        var oscillator = Oscillator(waveform: .sine)
        var out: [Double] = []
        for _ in 0..<Int(rate * 3) {
            let input = oscillator.render(frequency: 440, sampleRate: rate)
            out.append(chorus.process(left: input, right: input).left)
        }
        // A steady tone through a moving delay comes out with its level
        // wobbling; through a still one it would not.
        let early = rms(Array(out[Int(rate)..<Int(rate * 1.2)]))
        let later = rms(Array(out[Int(rate * 2)..<Int(rate * 2.2)]))
        #expect(early > 0.1 && later > 0.1)
        #expect(out.allSatisfy { $0.isFinite })
    }

    @Test("The ping-pong delay lands on one side, then the other")
    func pingPongAlternates() {
        var delay = PingPongDelay(delayTime: 0.05, feedback: 0.5, wet: 1, sampleRate: rate)
        var left: [Double] = []
        var right: [Double] = []
        for i in 0..<Int(rate * 0.3) {
            let out = delay.process(left: i == 0 ? 1 : 0, right: i == 0 ? 1 : 0)
            left.append(out.left)
            right.append(out.right)
        }
        let firstLeft = left.firstIndex { abs($0) > 0.01 }
        let firstRight = right.firstIndex { abs($0) > 0.01 }
        #expect(firstLeft != nil && firstRight != nil)
        // The right side is one delay behind the left.
        #expect(abs(Double((firstRight ?? 0) - (firstLeft ?? 0)) - rate * 0.05) < 2)
    }

    @Test("The delay decays instead of running away")
    func pingPongDecays() {
        var delay = PingPongDelay(delayTime: 0.05, feedback: 0.5, wet: 1, sampleRate: rate)
        var late = 0.0
        for i in 0..<Int(rate * 20) {
            let out = delay.process(left: i == 0 ? 1 : 0, right: 0)
            if i > Int(rate * 15) { late = max(late, abs(out.left)) }
        }
        #expect(late < 1e-4)
    }

    @Test("Distortion is gentle in the middle and firm at the edges")
    func distortionCurve() {
        let amount = 0.08
        // Small signals pass close to untouched, loud ones are pulled in.
        #expect(abs(Distortion.shape(0.05, amount: amount) - 0.05) < 0.02)
        #expect(Distortion.shape(1, amount: amount) < 1)
        // And it is odd-symmetric, which is what keeps it musical.
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(
                abs(Distortion.shape(x, amount: amount) + Distortion.shape(-x, amount: amount))
                    < 1e-12)
        }
    }
}

@Suite("Reverb")
struct ReverbTests {
    @Test("It rings on after the sound has stopped")
    func tail() {
        var reverb = Reverb(decay: 7, sampleRate: rate)
        var out: [Double] = []
        for i in 0..<Int(rate * 4) {
            let input = i < Int(rate * 0.05) ? sin(Double(i) * 0.05) : 0
            out.append(reverb.process(left: input, right: input).left)
        }
        // Two seconds after the source stopped there is still a room.
        let late = rms(Array(out[Int(rate * 2)..<Int(rate * 2.5)]))
        #expect(late > 1e-4, "the tail died at \(late)")
    }

    @Test("A seven-second decay is quieter than a one-second decay")
    func decayLength() {
        func energyAfter(_ decay: Double) -> Double {
            var reverb = Reverb(decay: decay, sampleRate: rate)
            var out: [Double] = []
            for i in 0..<Int(rate * 3) {
                let input = i < 100 ? 1.0 : 0
                out.append(reverb.process(left: input, right: input).left)
            }
            return rms(Array(out[Int(rate * 2)...]))
        }
        #expect(energyAfter(7) > energyAfter(1) * 5)
    }

    @Test("It settles rather than building up")
    func stable() {
        var reverb = Reverb(decay: 7, sampleRate: rate)
        var peak = 0.0
        for i in 0..<Int(rate * 30) {
            let out = reverb.process(left: i < 100 ? 1 : 0, right: 0)
            peak = max(peak, abs(out.left))
            if i > Int(rate * 25) { #expect(abs(out.left) < 1e-3) }
        }
        #expect(peak < 4)
    }

    @Test("The two sides are not the same signal")
    func stereo() {
        var reverb = Reverb(sampleRate: rate)
        var different = false
        for i in 0..<Int(rate) {
            let out = reverb.process(left: i < 100 ? 1 : 0, right: i < 100 ? 1 : 0)
            if abs(out.left - out.right) > 1e-6 { different = true }
        }
        #expect(different)
    }
}

@Suite("Limiter")
struct LimiterTests {
    @Test("Quiet signals pass untouched")
    func belowKnee() {
        #expect(Limiter.gainReduction(forLevel: -40) == 0)
        #expect(Limiter.gainReduction(forLevel: -24) == 0)
    }

    @Test("Loud signals are pulled toward the threshold")
    func aboveKnee() {
        let output = 12 + Limiter.gainReduction(forLevel: 12)
        #expect(abs(output - (-8 + 20 / 12.0)) < 1e-9)
        let louder = 24 + Limiter.gainReduction(forLevel: 24)
        #expect(abs((louder - output) - 1) < 1e-9)
    }

    /// What a soft knee is: the ratio arrives gradually rather than
    /// switching on.
    @Test("Across the knee the ratio climbs from 1:1 to the full ratio")
    func kneeSlope() {
        func slope(at dB: Double) -> Double {
            let h = 1e-4
            let low = dB - h + Limiter.gainReduction(forLevel: dB - h)
            let high = dB + h + Limiter.gainReduction(forLevel: dB + h)
            return (high - low) / (2 * h)
        }

        let kneeStart = Limiter.threshold - Limiter.knee / 2
        let kneeEnd = Limiter.threshold + Limiter.knee / 2

        #expect(abs(slope(at: kneeStart - 5) - 1) < 1e-6)
        #expect(abs(slope(at: kneeEnd + 5) - 1 / Limiter.ratio) < 1e-6)

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
            #expect(reduction <= 1e-12)
            #expect(reduction <= previous + 1e-9)
            #expect(abs(reduction - previous) < 0.5)
            previous = reduction
        }
    }

    @Test("A sustained loud tone is brought down")
    func holdsLoudMaterial() {
        var limiter = Limiter(sampleRate: rate)
        var peak = 0.0
        for i in 0..<Int(rate) {
            let x = sin(2 * Double.pi * 220 * Double(i) / rate)
            let out = limiter.process(left: x, right: x)
            if i > Int(rate / 2) { peak = max(peak, abs(out.left)) }
        }
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
        var peak = 0.0
        for i in 0..<Int(rate) {
            let x = 0.05 * sin(2 * Double.pi * 220 * Double(i) / rate)
            let out = limiter.process(left: x, right: x)
            if i > Int(rate / 2) { peak = max(peak, abs(out.left)) }
        }
        #expect(peak > 0.045)
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
