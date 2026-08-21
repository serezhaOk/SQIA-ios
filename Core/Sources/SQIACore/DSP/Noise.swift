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
    /// Paul Kellett's pink filter, the full seven-section form Tone uses
    /// rather than the three-section economy one.
    ///
    /// The short version is only accurate over the middle of the range and
    /// runs hot underneath it, which matters more than it sounds like it
    /// should: KALIMBA pours this into a comb whose response peaks at zero
    /// hertz as hard as it peaks at the note, so whatever sits at the bottom
    /// of the excitation is rung for the length of the note.
    private var b0 = 0.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var b3 = 0.0
    private var b4 = 0.0
    private var b5 = 0.0
    private var b6 = 0.0

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
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.153852
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.016898
            let value = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
            // b6 holds the previous sample's white, which is why it is set
            // after it has been read.
            b6 = w * 0.115926
            return value
        }
    }

    public mutating func reset() {
        b0 = 0
        b1 = 0
        b2 = 0
        b3 = 0
        b4 = 0
        b5 = 0
        b6 = 0
    }
}
