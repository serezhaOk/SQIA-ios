// The colouring every preset plays through: a chorus that will not sit
// still, a delay that throws the echo across the stereo field, and the
// overdrive the 303 runs into.
//
// Ported from the Tone.js nodes the web app builds in src/synths.ts, with
// the same defaults.

import Foundation

/// Two modulated delay lines in opposition — the left one lengthens while
/// the right one shortens, which is what widens the sound.
public struct Chorus: Sendable {
    public static let defaultFrequency = 0.45
    /// Base delay, in milliseconds. Tone takes it in ms and so does the web.
    public static let defaultDelayTime = 6.0
    /// Half a cycle apart, which is Tone's default spread of 180 degrees.
    public static let phaseOffset = 0.5

    public var frequency: Double
    public var delayTime: Double
    /// 0…1. Drifts once a bar rather than being ramped, because ramping a
    /// modulation depth steps it and clicks.
    public var depth: Double
    public var wet: Double

    private var left: DelayLine
    private var right: DelayLine
    private let sampleRate: Double

    /// The modulation, as a unit vector turned a fixed angle each sample
    /// rather than a sine evaluated at a phase. Two trigonometric calls per
    /// sample per preset is a great deal of arithmetic for one slow wobble.
    private var lfoSine = 0.0
    private var lfoCosine = 1.0
    private let stepSine: Double
    private let stepCosine: Double
    /// The rotation drifts off the unit circle over hours; nudging it back
    /// now and then costs nothing.
    private var sinceNormalise = 0

    public init(
        frequency: Double = defaultFrequency,
        delayTime: Double = defaultDelayTime,
        depth: Double = 0.55,
        wet: Double,
        sampleRate: Double
    ) {
        self.frequency = frequency
        self.delayTime = delayTime
        self.depth = depth
        self.wet = wet
        self.sampleRate = sampleRate
        let angle = 2 * Double.pi * frequency / sampleRate
        stepSine = sin(angle)
        stepCosine = cos(angle)
        // Room for the base delay and all of the modulation around it.
        left = DelayLine(maximum: 0.1, delay: delayTime / 1000, sampleRate: sampleRate)
        right = DelayLine(maximum: 0.1, delay: delayTime / 1000, sampleRate: sampleRate)
    }

    public mutating func clear() {
        left.clear()
        right.clear()
        lfoSine = 0
        lfoCosine = 1
        sinceNormalise = 0
    }

    public mutating func process(
        left input: Double,
        right inputRight: Double
    ) -> (left: Double, right: Double) {
        let base = delayTime / 1000 * sampleRate
        let swing = base * min(max(depth, 0), 1)

        // Half a cycle apart is simply the opposite sign, so one oscillator
        // does for both sides.
        let lfoLeft = lfoSine
        let lfoRight = -lfoSine

        let turnedSine = lfoSine * stepCosine + lfoCosine * stepSine
        let turnedCosine = lfoCosine * stepCosine - lfoSine * stepSine
        lfoSine = turnedSine
        lfoCosine = turnedCosine

        sinceNormalise += 1
        if sinceNormalise >= 4096 {
            sinceNormalise = 0
            let magnitude = (lfoSine * lfoSine + lfoCosine * lfoCosine).squareRoot()
            if magnitude > 1e-9 {
                lfoSine /= magnitude
                lfoCosine /= magnitude
            }
        }

        let wetLeft = left.process(input, delaySamples: base + swing * lfoLeft)
        let wetRight = right.process(inputRight, delaySamples: base + swing * lfoRight)

        let mix = min(max(wet, 0), 1)
        return (
            input + (wetLeft - input) * mix,
            inputRight + (wetRight - inputRight) * mix
        )
    }
}

/// The echo bounces: what goes into the left line comes out on the right,
/// and back again, so a repeat crosses the field each time.
public struct PingPongDelay: Sendable {
    public static let defaultDelayTime = 0.32
    public static let defaultFeedback = 0.38

    public var feedback: Double
    public var wet: Double

    private var left: DelayLine
    private var right: DelayLine
    private var pendingLeft = 0.0
    private var pendingRight = 0.0
    private let sampleRate: Double

    public init(
        delayTime: Double = defaultDelayTime,
        feedback: Double = defaultFeedback,
        wet: Double,
        sampleRate: Double
    ) {
        self.feedback = feedback
        self.wet = wet
        self.sampleRate = sampleRate
        // Six sixteenths at the slowest tempo the app allows is 2.25 s;
        // anything more would be megabytes of line nobody can reach.
        left = DelayLine(maximum: 2.5, delay: delayTime, sampleRate: sampleRate)
        right = DelayLine(maximum: 2.5, delay: delayTime, sampleRate: sampleRate)
    }

    public mutating func setDelayTime(_ seconds: Double) {
        left.setDelay(seconds, sampleRate: sampleRate)
        right.setDelay(seconds, sampleRate: sampleRate)
    }

    public mutating func clear() {
        left.clear()
        right.clear()
        pendingLeft = 0
        pendingRight = 0
    }

    public mutating func process(
        left input: Double,
        right inputRight: Double
    ) -> (left: Double, right: Double) {
        // Tone sums the input to mono before the bounce, so the crossing is
        // the only thing that puts it either side.
        let mono = (input + inputRight) * 0.5

        let outLeft = left.process(mono + pendingRight * feedback)
        let outRight = right.process(outLeft)
        pendingLeft = outLeft
        pendingRight = outRight

        let mix = min(max(wet, 0), 1)
        return (
            input + (outLeft - input) * mix,
            inputRight + (outRight - inputRight) * mix
        )
    }
}

/// Tone's distortion curve, which is a well-travelled waveshaper: gentle in
/// the middle, hard at the edges, and harder the more you ask for.
public struct Distortion: Sendable {
    public var amount: Double
    public var wet: Double

    public init(amount: Double, wet: Double = 0.5) {
        self.amount = amount
        self.wet = wet
    }

    public static func shape(_ x: Double, amount: Double) -> Double {
        let k = amount * 100
        let degrees = Double.pi / 180
        return (3 + k) * x * 20 * degrees / (.pi + k * abs(x))
    }

    public func process(_ x: Double) -> Double {
        let shaped = Self.shape(x, amount: amount)
        let mix = min(max(wet, 0), 1)
        return x + (shaped - x) * mix
    }
}
