// The room every preset sends into.
//
// The web builds a seven-second impulse and convolves against it. Doing the
// same here would mean a partitioned FFT convolution; this is the other
// standard answer — a feedback delay network, four lines whose outputs are
// mixed back into each other so the echoes multiply into a wash rather than
// repeating. Cheaper, and the character is adjustable in a way a fixed
// impulse is not.
//
// That makes it the one part of the chain that is a different construction
// rather than a port, so it goes on the A/B list for M9 along with the
// limiter. If it does not hold up, the fallback is the convolution.

import Foundation

public struct Reverb: Sendable {
    /// Seconds to fall sixty decibels — the web's impulse is built for this.
    public static let defaultDecay = 7.0
    public static let defaultPreDelay = 0.02

    /// Lengths in seconds, mutually prime so their repeats do not line up
    /// into a flutter.
    private static let delays = (0.0297, 0.0371, 0.0411, 0.0437)
    /// Where the top end is rolled off inside the loop, so the tail darkens
    /// as it fades the way a real room does.
    private static let damping = 4500.0

    /// A one-pole lowpass, and deliberately not a biquad. A biquad at Q = 1
    /// has a resonant peak of about a decibel, and a decibel of gain inside
    /// a loop already running at 0.96 is a loop running above unity — which
    /// is to say a howl rather than a room. A one-pole cannot peak.
    private struct OnePole: Sendable {
        private let coefficient: Double
        private var value = 0.0

        init(frequency: Double, sampleRate: Double) {
            coefficient = 1 - exp(-2 * .pi * frequency / sampleRate)
        }

        mutating func process(_ x: Double) -> Double {
            value += (x - value) * coefficient
            return value
        }

        mutating func reset() {
            value = 0
        }
    }

    // Four lines, written out rather than held in an array: the render loop
    // must not allocate, and an array of four would be one more thing that
    // could.
    private var lineA: DelayLine
    private var lineB: DelayLine
    private var lineC: DelayLine
    private var lineD: DelayLine
    private var dampA: OnePole
    private var dampB: OnePole
    private var dampC: OnePole
    private var dampD: OnePole

    /// What the mixing matrix fed back on the previous frame. A single
    /// sample of lag in the loop, which is what lets each line be read and
    /// written once.
    private var pendingA = 0.0
    private var pendingB = 0.0
    private var pendingC = 0.0
    private var pendingD = 0.0

    private var preDelayLeft: DelayLine
    private var preDelayRight: DelayLine
    private var feedbackGain: Double

    public init(
        decay: Double = defaultDecay,
        preDelay: Double = defaultPreDelay,
        sampleRate: Double
    ) {
        let (a, b, c, d) = Self.delays
        lineA = DelayLine(maximum: 0.2, delay: a, sampleRate: sampleRate)
        lineB = DelayLine(maximum: 0.2, delay: b, sampleRate: sampleRate)
        lineC = DelayLine(maximum: 0.2, delay: c, sampleRate: sampleRate)
        lineD = DelayLine(maximum: 0.2, delay: d, sampleRate: sampleRate)

        let damper = OnePole(frequency: Self.damping, sampleRate: sampleRate)
        dampA = damper
        dampB = damper
        dampC = damper
        dampD = damper

        preDelayLeft = DelayLine(
            maximum: 0.5, delay: max(preDelay, 0.001), sampleRate: sampleRate)
        preDelayRight = DelayLine(
            maximum: 0.5, delay: max(preDelay, 0.001), sampleRate: sampleRate)

        // Sixty decibels over `decay` seconds, spread across a loop whose
        // average trip is the mean of the four lengths.
        let average = (a + b + c + d) / 4
        feedbackGain = pow(10, -3 * average / max(decay, 0.05))
    }

    public mutating func clear() {
        lineA.clear()
        lineB.clear()
        lineC.clear()
        lineD.clear()
        dampA.reset()
        dampB.reset()
        dampC.reset()
        dampD.reset()
        pendingA = 0
        pendingB = 0
        pendingC = 0
        pendingD = 0
        preDelayLeft.clear()
        preDelayRight.clear()
    }

    public mutating func process(
        left: Double,
        right: Double
    ) -> (left: Double, right: Double) {
        let inLeft = preDelayLeft.process(left)
        let inRight = preDelayRight.process(right)
        let mono = (inLeft + inRight) * 0.5

        let a = dampA.process(lineA.process(mono + pendingA * feedbackGain))
        let b = dampB.process(lineB.process(mono + pendingB * feedbackGain))
        let c = dampC.process(lineC.process(mono + pendingC * feedbackGain))
        let d = dampD.process(lineD.process(mono + pendingD * feedbackGain))

        // A Hadamard mix: every line feeds every other, which is what turns
        // four echoes into a room instead of four echoes.
        pendingA = (a + b + c + d) * 0.5
        pendingB = (a - b + c - d) * 0.5
        pendingC = (a + b - c - d) * 0.5
        pendingD = (a - b - c + d) * 0.5

        // A different pair to each side, so the tail is wide.
        return ((a + c) * 0.5, (b + d) * 0.5)
    }
}
