// A plucked string, the Karplus-Strong way: fill a delay line one wavelength
// long with noise and let it circulate, losing a little on every lap.
//
// Port of what Tone's PluckSynth is made of — a one-pole lowpass into a
// feedback comb — because the sound is entirely in those two numbers.
// `dampening` decides how bright the pluck arrives, `resonance` how long the
// tine rings, and KALIMBA rolls both on every note.
//
// One thing worth naming: Tone dampens the burst on the way in rather than
// once per lap, so the tone does not darken as it decays the way a real
// string does. That is what the web sounds like, so it is what this does.

import Foundation

/// Tone's one-pole, coefficient and all.
///
/// The exact form would be `1 − exp(−2πf/fs)`; Tone uses the first-order
/// approximation `2πf/fs`, and at a dampening of 4.5 kHz the two differ by
/// enough to hear (0.59 against 0.45). Matching the web means matching the
/// approximation.
struct OnePoleLowpass: Sendable {
    private let coefficient: Double
    private var value = 0.0

    init(frequency: Double, sampleRate: Double) {
        coefficient = min(1, max(0, 2 * .pi * frequency / sampleRate))
    }

    mutating func process(_ x: Double) -> Double {
        value += (x - value) * coefficient
        return value
    }

    mutating func reset() {
        value = 0
    }
}

public struct Pluck: Sendable {
    /// The longest wavelength the line will ever hold — 20 Hz, well below
    /// anything the grid can ask for.
    public static let maximumPeriod = 0.05

    private var line: DelayLine
    private var damping = OnePoleLowpass(frequency: 2000, sampleRate: 48_000)
    private var noise = Noise(colour: .pink)
    private var resonance = 0.0
    /// Frames of noise at the start. Tone measures the burst in wavelengths,
    /// which is why a low note gets a longer one.
    private var burstFrames = 0
    private var age = 0
    private let sampleRate: Double

    /// Builds the line. The only place a pluck allocates, so it happens once
    /// per voice slot at start-up and never on the render thread.
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        line = DelayLine(
            maximum: Self.maximumPeriod, delay: Self.maximumPeriod, sampleRate: sampleRate)
    }

    /// Point it at a note. Touches nothing that could allocate.
    public mutating func start(
        frequency: Double,
        dampening: Double,
        resonance: Double,
        attackNoise: Double,
        seed: UInt32
    ) {
        let period = 1 / min(max(frequency, 20), 20_000)
        line.clear()
        line.setDelay(period, sampleRate: sampleRate)
        damping = OnePoleLowpass(frequency: dampening, sampleRate: sampleRate)
        noise = Noise(colour: .pink, seed: seed)
        self.resonance = min(0.999, max(0, resonance))
        burstFrames = max(1, Int(period * max(0, attackNoise) * sampleRate))
        age = 0
    }

    public mutating func next() -> Double {
        let excitation = age < burstFrames ? damping.process(noise.next()) : damping.process(0)
        age += 1

        // Read before writing: what goes back in is the input plus what just
        // came out, which is the whole of a feedback comb.
        let delayed = line.peek()
        line.push(excitation + delayed * resonance)
        return delayed
    }

    public mutating func clear() {
        line.clear()
        damping.reset()
        age = 0
    }
}
