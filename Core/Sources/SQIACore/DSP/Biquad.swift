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

    public init(bandpass frequency: Double, q: Double, sampleRate: Double) {
        setBandpass(frequency: frequency, q: q, sampleRate: sampleRate)
    }

    public init(highpass frequency: Double, q: Double = defaultQ, sampleRate: Double) {
        setHighpass(frequency: frequency, q: q, sampleRate: sampleRate)
    }

    /// Shared setup: the angular frequency and the bandwidth term every
    /// cookbook filter is built from. Nyquist and DC are both degenerate, so
    /// the frequency is clamped rather than allowed to divide by zero.
    private static func terms(
        _ frequency: Double, _ q: Double, _ sampleRate: Double
    ) -> (cosW0: Double, alpha: Double) {
        let nyquist = sampleRate / 2
        let f = min(max(frequency, 1), nyquist * 0.999)
        let w0 = 2 * Double.pi * f / sampleRate
        return (cos(w0), sin(w0) / (2 * max(q, 1e-4)))
    }

    /// The same, but with Q read the way Web Audio reads it for a lowpass or
    /// a highpass — in decibels.
    ///
    /// This is a real trap and not a small one. The spec uses `alphaQ` for
    /// bandpass, notch and allpass, where Q is the quality factor as anyone
    /// would expect, but `alphaQdB = sin(w0) / (2 · 10^(Q/20))` for lowpass
    /// and highpass, where the number is the height of the resonant peak in
    /// decibels. So a lowpass the web sets to Q = 15 has a quality factor of
    /// 5.6, not 15 — and two of them cascaded is thirty decibels of
    /// resonance rather than forty-seven.
    private static func termsFromDecibels(
        _ frequency: Double, _ q: Double, _ sampleRate: Double
    ) -> (cosW0: Double, alpha: Double) {
        terms(frequency, pow(10, q / 20), sampleRate)
    }

    public mutating func setLowpass(frequency: Double, q: Double, sampleRate: Double) {
        let (cosW0, alpha) = Self.termsFromDecibels(frequency, q, sampleRate)
        let a0 = 1 + alpha
        b0 = ((1 - cosW0) / 2) / a0
        b1 = (1 - cosW0) / a0
        b2 = b0
        a1 = (-2 * cosW0) / a0
        a2 = (1 - alpha) / a0
    }

    public mutating func setHighpass(frequency: Double, q: Double, sampleRate: Double) {
        let (cosW0, alpha) = Self.termsFromDecibels(frequency, q, sampleRate)
        let a0 = 1 + alpha
        b0 = ((1 + cosW0) / 2) / a0
        b1 = -(1 + cosW0) / a0
        b2 = b0
        a1 = (-2 * cosW0) / a0
        a2 = (1 - alpha) / a0
    }

    /// Constant-skirt bandpass, peaking at Q — what Web Audio's bandpass is.
    public mutating func setBandpass(frequency: Double, q: Double, sampleRate: Double) {
        let (cosW0, alpha) = Self.terms(frequency, q, sampleRate)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
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
