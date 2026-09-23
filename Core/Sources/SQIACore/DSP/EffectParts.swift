// Small parts the master effects are built from.
//
// Everything here is a value with its memory sized up front, so the render
// thread can use it without allocating.

import Foundation

/// A circular buffer written once a sample and read anywhere behind the
/// write — between samples, and at several places at once, which is what a
/// granular delay and a beat repeat need and `DelayLine` cannot do.
struct RingBuffer: Sendable {
    private var buffer: [Double]
    private var writeIndex = 0
    /// Samples written since the start. A position in this count names one
    /// sample for as long as it is still in the buffer.
    private(set) var written = 0

    init(seconds: Double, sampleRate: Double) {
        buffer = Array(repeating: 0, count: max(8, Int((seconds * sampleRate).rounded(.up)) + 4))
    }

    /// How far back a read can reach, in samples.
    var reach: Double { Double(buffer.count - 3) }

    mutating func write(_ x: Double) {
        buffer[writeIndex] = x
        writeIndex += 1
        if writeIndex == buffer.count { writeIndex = 0 }
        written += 1
    }

    /// The sample written `delay` samples ago, where 1 is the one just
    /// written. Fractional delays are read by straight-line interpolation.
    func read(delay: Double) -> Double {
        let wanted = min(max(delay, 1), reach)
        let whole = Int(wanted)
        let fraction = wanted - Double(whole)
        var first = writeIndex - whole
        if first < 0 { first += buffer.count }
        var second = first - 1
        if second < 0 { second += buffer.count }
        return buffer[first] + (buffer[second] - buffer[first]) * fraction
    }

    /// The sample at `position` in the running count.
    func read(at position: Double) -> Double {
        read(delay: Double(written) - position)
    }

    mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
        writeIndex = 0
        written = 0
    }
}

/// A value that slides toward where it is told to be rather than jumping,
/// so a knob turned under a playing sound does not step it.
struct Glide: Sendable {
    var value: Double
    var target: Double
    private let rate: Double

    init(_ value: Double, seconds: Double, sampleRate: Double) {
        self.value = value
        target = value
        rate = 1 - exp(-1 / max(1, seconds * sampleRate))
    }

    mutating func next() -> Double {
        let gap = target - value
        // Arrive exactly. A send that only approaches zero never lets the
        // effect behind it be skipped, and never lets it be a true bypass.
        if abs(gap) < 1e-9 {
            value = target
        } else {
            value += gap * rate
        }
        return value
    }

    mutating func snap() {
        value = target
    }
}

struct SmoothingLowpass: Sendable {
    private var coefficient: Double
    private var state = 0.0

    init(frequency: Double, sampleRate: Double) {
        coefficient = 1 - exp(-2 * .pi * frequency / sampleRate)
    }

    mutating func process(_ x: Double) -> Double {
        state += (x - state) * coefficient
        return state
    }

    mutating func reset() { state = 0 }
}

struct SmoothingHighpass: Sendable {
    private var low: SmoothingLowpass

    init(frequency: Double, sampleRate: Double) {
        low = SmoothingLowpass(frequency: frequency, sampleRate: sampleRate)
    }

    mutating func process(_ x: Double) -> Double {
        x - low.process(x)
    }

    mutating func reset() { low.reset() }
}

/// xorshift64*. The render thread needs dice it can roll without a lock or
/// a system call, and nothing here needs them to be good dice.
struct EffectRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    /// Uniform in 0..<1.
    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let mixed = state &* 0x2545_F491_4F6C_DD1D
        return Double(mixed >> 11) / Double(UInt64(1) << 53)
    }
}

/// The first half of a knob does most of the work: the send rises quickly
/// and then settles, so a third of the way round is already clearly heard.
@inline(__always)
func knobCurve(_ amount: Double) -> Double {
    let a = min(max(amount, 0), 1)
    return 1 - (1 - a) * (1 - a)
}

/// A soft ceiling for anything fed back into itself: transparent near
/// silence, bending toward ±1 past it, so a loop pushed too far saturates
/// like tape rather than running away.
@inline(__always)
func softClip(_ x: Double) -> Double {
    if x > 3 { return 1 }
    if x < -3 { return -1 }
    let x2 = x * x
    return x * (27 + x2) / (27 + 9 * x2)
}
