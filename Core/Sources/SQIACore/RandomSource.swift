// Where every random decision in SQIA comes from.
//
// The web app calls Math.random() directly, which makes its behaviour
// impossible to pin down in a test. Here the stream is a parameter instead,
// so production uses the system generator while the tests replay the exact
// sequence the web app produced.

/// A stream of doubles in `[0, 1)` — the shape of `Math.random()`.
///
/// A class rather than a value type on purpose: a generator is one shared
/// stream, and handing it to a grid or a voice must advance the same stream
/// the caller holds.
public protocol RandomSource: AnyObject {
    func next() -> Double
}

/// The system generator. What the app runs on.
public final class SystemRandomSource: RandomSource {
    public init() {}

    public func next() -> Double {
        Double.random(in: 0..<1)
    }
}

/// Mulberry32 — small, seedable, and reproducible in JavaScript, which is
/// what makes it the bridge to the web app's behaviour.
///
/// Every step stays inside 32 bits. JavaScript's `^`, `>>>`, `|` and
/// `Math.imul` all work mod 2^32 already, so the same arithmetic in `UInt32`
/// lands on identical bits and the two platforms walk the same sequence.
/// `RandomSourceTests` checks that against a fixture rather than trusting it.
public final class Mulberry32: RandomSource {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    public func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (state | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

extension RandomSource {
    /// `a + Math.random() * (b - a)` — the web app's `rnd` helper.
    public func value(_ a: Double, _ b: Double) -> Double {
        a + next() * (b - a)
    }

    /// `Math.random() < p`. Consumes one value whatever the answer.
    public func chance(_ p: Double) -> Bool {
        next() < p
    }

    /// `Math.floor(Math.random() * count)`.
    public func index(_ count: Int) -> Int {
        Int(next() * Double(count))
    }

    public func pick<T>(_ elements: [T]) -> T {
        elements[index(elements.count)]
    }
}
