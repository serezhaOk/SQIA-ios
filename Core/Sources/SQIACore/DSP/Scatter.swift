// The mixer's Scatter, after the SP-404's: the pattern caught on a step and
// stuttered.
//
// On a step boundary the dice decide whether to catch what is coming. If
// they do, a slice of it — a couple of steps, one, half, a quarter — plays
// through once as it arrives and then again and again until the repeat
// runs out, on a later step boundary so the pattern picks up on the grid.
// A repeat may run backwards after its first pass, or at half speed, which
// drops it an octave. The knob is the depth: how often it catches, how fine
// it cuts, and how strange it is allowed to get.
//
// The step grid comes from the transport, as the frame a step lands on and
// how long a step is, so a stutter starts where a note does.

import Foundation

public struct Scatter: Sendable {
    /// How long a slice may be, in steps, from the plainest to the finest.
    private static let divisions = (2.0, 1.0, 0.5, 0.25)

    private var left: RingBuffer
    private var right: RingBuffer
    private var mix: Glide
    private var amount = 0.0
    private var dice: EffectRandom
    private let sampleRate: Double
    /// The edge of every repeated pass is faded over this many samples, so
    /// the cut is heard as a stutter and not as a click.
    private let fade: Double

    // The grid.
    private var origin: Int64 = 0
    private var stepFrames = 0.0
    private var nextStep = Int64.max
    private var lastTick = Int64.min / 2

    // The repeat.
    public private(set) var isRepeating = false
    private var sliceStart = 0.0
    private var sliceLength = 1.0
    private var position = 0.0
    private var pass = 0
    private var stepsLeft = 0
    private var reverse = false
    private var rate = 1.0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        // Eight steps at the slowest tempo is three seconds.
        left = RingBuffer(seconds: 3.6, sampleRate: sampleRate)
        right = RingBuffer(seconds: 3.6, sampleRate: sampleRate)
        mix = Glide(0, seconds: 0.002, sampleRate: sampleRate)
        fade = 0.0015 * sampleRate
        dice = EffectRandom(seed: 0x5CA7)
    }

    public mutating func setAmount(_ amount: Double) {
        self.amount = min(max(amount, 0), 1)
    }

    /// Where the steps fall: `frame` is one of them, and they come every
    /// `stepSeconds` either side of it.
    ///
    /// The transport sends this every step, a little late — it travels
    /// behind the notes — so a step already ticked from the previous grid
    /// is not ticked again.
    public mutating func setGrid(frame: Int64, stepSeconds: Double) {
        origin = frame
        stepFrames = max(1, stepSeconds * sampleRate)
        var next = Double(frame)
        let guardLine = Double(lastTick) + stepFrames * 0.5
        if next <= guardLine {
            next += ((guardLine - next) / stepFrames).rounded(.down) * stepFrames + stepFrames
        }
        nextStep = Int64(next.rounded())
    }

    public var isActive: Bool { amount > 0 || isRepeating || mix.value != 0 }

    public mutating func clear() {
        left.clear()
        right.clear()
        isRepeating = false
        mix.target = 0
        mix.snap()
        nextStep = .max
        lastTick = .min / 2
    }

    public mutating func process(left inLeft: Double, right inRight: Double, frame: Int64)
        -> (left: Double, right: Double)
    {
        // The tick comes before the write, so a slice caught here starts
        // with this very sample.
        if frame >= nextStep {
            tick()
            lastTick = frame
            let steps = (Double(frame - origin) / stepFrames).rounded(.down) + 1
            nextStep = origin + Int64((steps * stepFrames).rounded())
        }

        left.write(inLeft)
        right.write(inRight)

        let m = mix.next()
        if m == 0 { return (inLeft, inRight) }

        let within = reverse && pass > 0 ? sliceLength - 1 - position : position
        let at = sliceStart + max(0, within)
        let heldLeft = left.read(at: at)
        let heldRight = right.read(at: at)

        // The first pass is the sound arriving, and it arrives unbroken; every
        // edge after that is a cut, and is faded.
        let fromStart = pass == 0 ? fade : position
        let edge = min(1, fromStart / fade, (sliceLength - position) / fade)

        position += rate
        if position >= sliceLength {
            position -= sliceLength
            pass += 1
        }

        let outLeft = heldLeft * edge
        let outRight = heldRight * edge
        return (inLeft + (outLeft - inLeft) * m, inRight + (outRight - inRight) * m)
    }

    private mutating func tick() {
        if isRepeating {
            stepsLeft -= 1
            guard stepsLeft <= 0 else { return }
            isRepeating = false
            mix.target = 0
        }
        guard amount > 0, dice.next() < 0.6 * amount else { return }
        start()
    }

    private mutating func start() {
        let (two, one, half, quarter) = Self.divisions
        // Deeper lets it cut finer.
        let choices = amount < 0.35 ? 2 : amount < 0.7 ? 3 : 4
        let division: Double
        switch Int(dice.next() * Double(choices)) {
        case 0: division = two
        case 1: division = one
        case 2: division = half
        default: division = quarter
        }

        sliceLength = max(64, (stepFrames * division).rounded())
        sliceStart = Double(left.written)
        position = 0
        pass = 0
        reverse = dice.next() < 0.15 + 0.35 * amount
        rate = dice.next() < 0.3 * amount ? 0.5 : 1

        // Long enough to hear the slice come round at least once more, and
        // never so long that the start of it has been written over.
        let atLeast = Int(division.rounded(.up)) * 2
        let wanted = 2 + Int(dice.next() * (1 + 6 * amount))
        let room = Int((left.reach - sliceLength * 2) / stepFrames)
        stepsLeft = min(max(atLeast, wanted), max(1, room))

        isRepeating = true
        mix.target = 1
    }
}
