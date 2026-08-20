// The master limiter — the last thing every voice passes through.
//
// The web uses Web Audio's DynamicsCompressorNode at threshold −8 dB, ratio
// 12:1, attack 3 ms, release 180 ms. That node is a specific implementation
// with a soft knee, a short lookahead and an adaptive release; this is a
// conventional soft-knee compressor set to the same numbers, with the same
// 6 ms lookahead, which is close but not that implementation reproduced.
//
// It sits on the master bus, so it colours everything — worth an A/B against
// the web before release (M9).

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

    /// Below the knee nothing is compressed at all, so a quiet passage can
    /// skip the whole computation.
    private static let quietPeak = 0.0708  // −23 dBFS, the knee's lower edge

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

    /// Gain reduction the static curve asks for at an input level, in dB.
    ///
    /// Below the knee the signal passes; across the knee the ratio comes in
    /// gradually (a quadratic blend, which is what keeps a limiter from
    /// sounding like it switches on); above it, the full ratio applies.
    public static func gainReduction(forLevel dB: Double) -> Double {
        let over = dB - threshold
        if over <= -knee / 2 { return 0 }
        if over >= knee / 2 {
            return threshold + over / ratio - dB
        }
        let x = over + knee / 2
        return (1 / ratio - 1) * x * x / (2 * knee)
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

        return (lookaheadLeft.process(left) * gain, lookaheadRight.process(right) * gain)
    }
}
