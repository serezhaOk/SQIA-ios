// The master limiter — the last thing every voice passes through.
//
// The web uses Web Audio's DynamicsCompressorNode at threshold −8 dB, ratio
// 12:1, and the node's own defaults for the rest. It sits on the master bus,
// so whatever it does, it does to everything.
//
// The static curve below is Blink's, ported (M9). It was a conventional
// soft-knee compressor at the same numbers, and "the same numbers" turned
// out not to mean the same curve at all: a textbook knee is centred on the
// threshold, so it starts working 15 dB below it, while Blink's runs from
// the threshold upward. At −8 with a 30 dB knee the two disagree about
// everything between −23 and +22 dBFS, which is most of the music. The port
// makes the master stop compressing what the web passes untouched.
//
// What is still not Blink's is the envelope — its release is adaptive and
// its attack curve is its own. That part is measured in `LimiterParityTests`
// and left as it is: the difference is in how fast the same reduction
// arrives, not in how much of it there is.

import Foundation

public struct Limiter: Sendable {
    /// dBFS at which compression starts.
    public static let threshold = -8.0
    public static let ratio = 12.0
    /// Width of the soft knee, in dB. Web Audio's default.
    public static let knee = 30.0
    public static let attack = 0.003
    public static let release = 0.18
    /// Web Audio's DynamicsCompressorNode reports 6 ms of latency; matching
    /// it means the gain is already falling when a transient arrives.
    public static let lookahead = 0.006

    /// The gain computer runs on a block of samples rather than each one.
    /// Its two logarithms are the most expensive thing on the master bus,
    /// and at 8 samples the attack still gets eighteen updates before it has
    /// finished — far more resolution than the ear has.
    private static let controlInterval = 8

    /// Below the threshold nothing is compressed at all, so a quiet passage
    /// can skip the whole computation. Blink's curve is linear right up to
    /// the threshold, so that is where this sits.
    private static let quietPeak = 0.398_107  // −8 dBFS

    private var lookaheadLeft: DelayLine
    private var lookaheadRight: DelayLine
    private var attackCoefficient: Double
    private var releaseCoefficient: Double

    /// Current gain, linear and always ≤ 1.
    private var gain = 1.0
    private var targetGain = 1.0
    private var blockPeak = 0.0
    private var sinceControl = 0

    public init(sampleRate: Double) {
        lookaheadLeft = DelayLine(maximum: 0.05, delay: Self.lookahead, sampleRate: sampleRate)
        lookaheadRight = DelayLine(maximum: 0.05, delay: Self.lookahead, sampleRate: sampleRate)
        attackCoefficient = Self.coefficient(Self.attack, sampleRate: sampleRate)
        releaseCoefficient = Self.coefficient(Self.release, sampleRate: sampleRate)
    }

    /// One-pole smoothing coefficient reaching ~63% of a step in `time`.
    private static func coefficient(_ time: Double, sampleRate: Double) -> Double {
        time <= 0 ? 0 : exp(-1 / (time * sampleRate))
    }

    public mutating func clear() {
        lookaheadLeft.clear()
        lookaheadRight.clear()
        gain = 1
        targetGain = 1
        blockPeak = 0
        sinceControl = 0
    }

    // ------------------------------------------------------- the curve --
    //
    // Blink's `DynamicsCompressor::Saturate`, in
    // third_party/blink/renderer/platform/audio/dynamics_compressor.cc.
    // Three pieces: linear below the threshold, an exponential knee from
    // the threshold to threshold + knee, and a straight line at 1/ratio
    // above that. The knee is derivative-matched at both ends, which is why
    // it is an exponential rather than the quadratic every textbook draws.

    private static let linearThreshold = pow(10, threshold / 20)
    private static let dBKneeThreshold = threshold + knee
    private static let kneeThreshold = pow(10, dBKneeThreshold / 20)

    /// The exponential the knee is made of, solved for the slope the ratio
    /// asks for. Blink finds it by fifteen rounds of bisection on the
    /// geometric mean; so does this, because a closed form would be a
    /// different number and the point is to be the same number.
    static let k: Double = {
        let x = kneeThreshold
        var x2 = 1.0
        var dBx2 = 0.0
        if !(x < linearThreshold) {
            x2 = x * 1.001
            dBx2 = 20 * log10(x2)
        }
        let dBx = dBKneeThreshold

        var minK = 0.1
        var maxK = 10000.0
        var k = 5.0
        let desired = 1 / ratio

        for _ in 0..<15 {
            var slope = 1.0
            if !(x < linearThreshold) {
                let dBy = 20 * log10(kneeCurve(x, k))
                let dBy2 = 20 * log10(kneeCurve(x2, k))
                slope = (dBy2 - dBy) / (dBx2 - dBx)
            }
            if slope < desired { maxK = k } else { minK = k }
            k = (minK * maxK).squareRoot()
        }
        return k
    }()

    private static let dBYKneeThreshold: Double = 20 * log10(kneeCurve(kneeThreshold, k))

    /// Linear to the threshold, then an exponential that approaches
    /// `linearThreshold + 1/k` from below.
    static func kneeCurve(_ x: Double, _ k: Double) -> Double {
        if x < linearThreshold { return x }
        return linearThreshold + (1 - exp(-k * (x - linearThreshold))) / k
    }

    /// The makeup Blink applies on the way out, `(1 / Saturate(1, k))^0.6`.
    /// A little over a quarter of a decibel — inaudible on its own, and the
    /// difference between having ported the node and having ported most of
    /// it.
    public static let postGain: Double = pow(1 / saturate(1), 0.6)

    /// The whole curve: what an input of `x` comes out as, linear in and
    /// linear out.
    public static func saturate(_ x: Double) -> Double {
        if x < kneeThreshold { return kneeCurve(x, k) }
        let dBx = 20 * log10(x)
        let dBy = dBYKneeThreshold + (dBx - dBKneeThreshold) / ratio
        return pow(10, dBy / 20)
    }

    /// Gain reduction the static curve asks for at an input level, in dB.
    public static func gainReduction(forLevel dB: Double) -> Double {
        let x = pow(10, dB / 20)
        guard x > 0 else { return 0 }
        return 20 * log10(saturate(x)) - dB
    }

    /// Process one stereo frame.
    public mutating func process(left: Double, right: Double) -> (left: Double, right: Double) {
        // Detect on the louder channel so the image does not wander.
        let peak = max(abs(left), abs(right))
        if peak > blockPeak { blockPeak = peak }

        sinceControl += 1
        if sinceControl >= Self.controlInterval {
            sinceControl = 0
            if blockPeak <= Self.quietPeak {
                targetGain = 1
            } else {
                let level = 20 * log10(blockPeak)
                targetGain = pow(10, Self.gainReduction(forLevel: level) / 20)
            }
            blockPeak = 0
        }

        // Attack when clamping down harder, release when letting go.
        let coefficient = targetGain < gain ? attackCoefficient : releaseCoefficient
        gain = targetGain + (gain - targetGain) * coefficient

        let out = gain * Self.postGain
        return (lookaheadLeft.process(left) * out, lookaheadRight.process(right) * out)
    }
}
