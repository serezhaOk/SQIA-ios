// A biquad filter, coefficients per the RBJ cookbook — the same formulas
// Web Audio's BiquadFilterNode uses, so a filter set to the same frequency
// and Q behaves the same on both platforms.

import Foundation

public struct Biquad: Sendable {
    /// Web Audio's BiquadFilterNode defaults to Q = 1.
    public static let defaultQ = 1.0

    private var b0: Double = 1
    private var b1: Double = 0
    private var b2: Double = 0
    private var a1: Double = 0
    private var a2: Double = 0

    // Direct form I state, one channel.
    private var x1: Double = 0
    private var x2: Double = 0
    private var y1: Double = 0
    private var y2: Double = 0

    public init(lowpass frequency: Double, q: Double = defaultQ, sampleRate: Double) {
        setLowpass(frequency: frequency, q: q, sampleRate: sampleRate)
    }

    public mutating func setLowpass(frequency: Double, q: Double, sampleRate: Double) {
        // Nyquist and DC are both degenerate; clamp rather than divide by zero.
        let nyquist = sampleRate / 2
        let f = min(max(frequency, 1), nyquist * 0.999)
        let w0 = 2 * Double.pi * f / sampleRate
        let cosW0 = cos(w0)
        let alpha = sin(w0) / (2 * max(q, 1e-4))

        let a0 = 1 + alpha
        b0 = ((1 - cosW0) / 2) / a0
        b1 = (1 - cosW0) / a0
        b2 = b0
        a1 = (-2 * cosW0) / a0
        a2 = (1 - alpha) / a0
    }

    public mutating func reset() {
        x1 = 0
        x2 = 0
        y1 = 0
        y2 = 0
    }

    public mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }

    /// Magnitude response at a frequency, for tests and for reasoning about
    /// a filter without listening to it.
    public func magnitude(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // Evaluate H(z) on the unit circle.
        let cos1 = cos(w), sin1 = sin(w)
        let cos2 = cos(2 * w), sin2 = sin(2 * w)
        let numReal = b0 + b1 * cos1 + b2 * cos2
        let numImag = -(b1 * sin1 + b2 * sin2)
        let denReal = 1 + a1 * cos1 + a2 * cos2
        let denImag = -(a1 * sin1 + a2 * sin2)
        let num = (numReal * numReal + numImag * numImag).squareRoot()
        let den = (denReal * denReal + denImag * denImag).squareRoot()
        return den == 0 ? .infinity : num / den
    }
}
