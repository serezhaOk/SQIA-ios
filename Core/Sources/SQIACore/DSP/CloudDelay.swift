// The mixer's Cloud, after the SP-404's cloud delay: an echo broken into
// grains, some of them an octave up, fed back into itself.
//
// A handful of short windowed reads float behind the write, each starting
// a little further back than the last and scattered across the stereo
// field, so what comes out is a haze around the sound rather than a copy of
// it. A grain read at twice the speed comes out an octave up; fed back, the
// octave climbs again on the next pass, which is where the shimmer comes
// from. The loop's lowpass is what stops it climbing out of hearing.

import Foundation

public struct CloudDelay: Sendable {
    /// How far a shifted grain is moved — an octave. 1.5 would be a fifth.
    public static let shift = 2.0
    /// How many grains out of ten are shifted; the rest are the sound at
    /// its own pitch, smeared.
    public static let shiftedShare = 0.55
    /// The echo sits a quarter note behind the sound.
    public static let steps = 4.0

    private struct Grain: Sendable {
        var active = false
        var age = 0.0
        var length = 1.0
        /// How far behind the write this grain is reading now.
        var delay = 0.0
        var rate = 1.0
        var gainLeft = 0.0
        var gainRight = 0.0
    }

    private static let grainCount = 8
    private static let windowSize = 1024

    private var line: RingBuffer
    private var grains: [Grain]
    /// Half a sine squared, looked up rather than computed: eight cosines a
    /// sample is more than the whole of the rest of this costs.
    private let window: [Double]
    private var untilNext = 0.0
    private var base: Glide
    private var send: Glide
    private var feedback: Glide
    private var tone: SmoothingLowpass
    private var cut: SmoothingHighpass
    private var dice: EffectRandom
    private let sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        line = RingBuffer(seconds: 2.2, sampleRate: sampleRate)
        grains = Array(repeating: Grain(), count: Self.grainCount)
        window = (0..<Self.windowSize).map { i in
            let phase = Double(i) / Double(Self.windowSize - 1)
            let s = sin(Double.pi * phase)
            return s * s
        }
        base = Glide(Self.steps * 0.125 * sampleRate, seconds: 0.2, sampleRate: sampleRate)
        send = Glide(0, seconds: 0.03, sampleRate: sampleRate)
        feedback = Glide(0, seconds: 0.03, sampleRate: sampleRate)
        tone = SmoothingLowpass(frequency: 5_500, sampleRate: sampleRate)
        cut = SmoothingHighpass(frequency: 260, sampleRate: sampleRate)
        dice = EffectRandom(seed: 0xC10D)
    }

    public mutating func setAmount(_ amount: Double) {
        let a = min(max(amount, 0), 1)
        send.target = knobCurve(a) * 1.1
        feedback.target = a == 0 ? 0 : 0.35 + 0.37 * a
    }

    public mutating func setStep(seconds: Double) {
        // Leave room behind it for the scatter of grain starts and for a
        // shifted grain, which reads toward the write as it plays.
        base.target = min(Self.steps * seconds * sampleRate, 1.2 * sampleRate)
    }

    public var isSending: Bool { send.value != 0 || send.target != 0 }

    public mutating func clear() {
        line.clear()
        for i in grains.indices { grains[i].active = false }
        tone.reset()
        cut.reset()
        untilNext = 0
        base.snap()
    }

    public mutating func process(left inLeft: Double, right inRight: Double)
        -> (left: Double, right: Double)
    {
        let amount = send.next()
        let back = feedback.next()
        let behind = base.next()

        untilNext -= 1
        if untilNext <= 0 { untilNext = spawn(behind: behind) }

        var outLeft = 0.0
        var outRight = 0.0
        var mono = 0.0
        let last = Double(Self.windowSize - 1)
        for i in grains.indices where grains[i].active {
            let grain = grains[i]
            let w = window[Int(grain.age / grain.length * last)]
            let x = line.read(delay: grain.delay) * w
            outLeft += x * grain.gainLeft
            outRight += x * grain.gainRight
            mono += x
            grains[i].age += 1
            // A grain read faster than the write gains on it.
            grains[i].delay -= grain.rate - 1
            if grains[i].age >= grain.length { grains[i].active = false }
        }

        let input = (inLeft + inRight) * 0.5 * amount
        let loop = cut.process(tone.process(mono)) * back
        line.write(input + softClip(loop))

        return (outLeft, outRight)
    }

    /// Start a grain, and say how long until the next one.
    private mutating func spawn(behind: Double) -> Double {
        let length = (0.07 + 0.11 * dice.next()) * sampleRate
        guard let slot = grains.firstIndex(where: { !$0.active }) else {
            return length * 0.25
        }

        let shifted = dice.next() < Self.shiftedShare
        // A few cents either way, so two grains at once beat against each
        // other rather than doubling.
        let rate = (shifted ? Self.shift : 1) * (1 + (dice.next() - 0.5) * 0.008)
        var delay = behind + dice.next() * 0.09 * sampleRate
        // A fast grain must not reach the write before it ends.
        delay = max(delay, (rate - 1) * length + 4)
        delay = min(delay, line.reach - 2)

        let pan = (dice.next() * 2 - 1) * 0.85
        grains[slot] = Grain(
            active: true, age: 0, length: length, delay: delay, rate: rate,
            gainLeft: ((1 - pan) * 0.5).squareRoot(),
            gainRight: ((1 + pan) * 0.5).squareRoot())

        // Two grains overlapping on average, which with this window sums to
        // roughly the level of the sound itself.
        return length * 0.5
    }
}
