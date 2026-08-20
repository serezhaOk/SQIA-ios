// Noise, which is most of a drum kit.
//
// White for snares and claps, pink where the web asks for it — Tone offers
// both and the machine preset picks between them per note.

public enum NoiseColour: Int, Sendable {
    case white
    case pink
}

public struct Noise: Sendable {
    public var colour: NoiseColour

    /// Its own generator, so a voice's noise never disturbs the stream the
    /// pattern is drawn from.
    private var state: UInt32
    /// Paul Kellett's pink filter: three one-pole sections that between them
    /// tilt white noise by three decibels an octave.
    private var b0 = 0.0
    private var b1 = 0.0
    private var b2 = 0.0

    public init(colour: NoiseColour = .white, seed: UInt32 = 0x9E37_79B9) {
        self.colour = colour
        state = seed | 1
    }

    private mutating func white() -> Double {
        // xorshift32 — cheap, and good enough that no one can hear the
        // period.
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / 2_147_483_648.0 - 1
    }

    public mutating func next() -> Double {
        let w = white()
        switch colour {
        case .white:
            return w
        case .pink:
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            return (b0 + b1 + b2 + w * 0.1848) * 0.2
        }
    }

    public mutating func reset() {
        b0 = 0
        b1 = 0
        b2 = 0
    }
}
