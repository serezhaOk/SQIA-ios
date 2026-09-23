// The mixer's Delay: a ping-pong echo on a dotted eighth, in time with the
// pattern.
//
// Every repeat goes back through a lowpass and a highpass on its way round,
// so the echoes darken and thin as they fade the way tape repeats do rather
// than ringing on as bright copies. When the tempo moves the time glides to
// its new length instead of jumping, which bends the pitch of whatever is
// in the line for a moment — the other thing tape does.

import Foundation

public struct TapeEcho: Sendable {
    /// Three sixteenths: the dotted eighth that sits against a straight
    /// pattern rather than on it.
    public static let steps = 3.0
    /// Where the repeats are cut to, top and bottom.
    public static let tone = 3_600.0
    public static let lowCut = 220.0

    private var left: RingBuffer
    private var right: RingBuffer
    private var time: Glide
    private var send: Glide
    private var feedback: Glide
    private var toneLeft: SmoothingLowpass
    private var toneRight: SmoothingLowpass
    private var cutLeft: SmoothingHighpass
    private var cutRight: SmoothingHighpass
    private let sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        // Three sixteenths at the slowest tempo is 1.125 s.
        left = RingBuffer(seconds: 1.3, sampleRate: sampleRate)
        right = RingBuffer(seconds: 1.3, sampleRate: sampleRate)
        time = Glide(Self.steps * 0.125 * sampleRate, seconds: 0.12, sampleRate: sampleRate)
        send = Glide(0, seconds: 0.03, sampleRate: sampleRate)
        feedback = Glide(0, seconds: 0.03, sampleRate: sampleRate)
        toneLeft = SmoothingLowpass(frequency: Self.tone, sampleRate: sampleRate)
        toneRight = SmoothingLowpass(frequency: Self.tone, sampleRate: sampleRate)
        cutLeft = SmoothingHighpass(frequency: Self.lowCut, sampleRate: sampleRate)
        cutRight = SmoothingHighpass(frequency: Self.lowCut, sampleRate: sampleRate)
    }

    /// 0…1. More of the signal goes in, and more of each repeat comes back.
    public mutating func setAmount(_ amount: Double) {
        let a = min(max(amount, 0), 1)
        send.target = knobCurve(a) * 0.85
        feedback.target = a == 0 ? 0 : 0.3 + 0.42 * a
    }

    public mutating func setStep(seconds: Double) {
        time.target = min(Self.steps * seconds * sampleRate, left.reach - 2)
    }

    /// Whether anything is still going in.
    public var isSending: Bool { send.value != 0 || send.target != 0 }

    public mutating func clear() {
        left.clear()
        right.clear()
        toneLeft.reset()
        toneRight.reset()
        cutLeft.reset()
        cutRight.reset()
        time.snap()
    }

    /// The echoes alone; the caller adds them to what it already has.
    public mutating func process(left inLeft: Double, right inRight: Double)
        -> (left: Double, right: Double)
    {
        let delay = time.next()
        let amount = send.next()
        let back = feedback.next()

        let outLeft = left.read(delay: delay)
        let outRight = right.read(delay: delay)

        // The input only goes in on the left; the right hears the left's
        // repeats, and feeds the left again. So an echo crosses the field
        // on every bounce.
        let mono = (inLeft + inRight) * 0.5 * amount
        let returnLeft = cutLeft.process(toneLeft.process(outRight)) * back
        let returnRight = cutRight.process(toneRight.process(outLeft)) * back
        left.write(mono + softClip(returnLeft))
        right.write(softClip(returnRight))

        return (outLeft, outRight)
    }
}
