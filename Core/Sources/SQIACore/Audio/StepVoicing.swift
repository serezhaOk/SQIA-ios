// What actually sounds on a step.
//
// "Random within the frame": full accents always fire, soft bleed cells fire
// with a probability tied to how bright they are, and every hit is humanised
// — velocity shimmer for all voices, plus a micro-detune and a re-rolled
// tail for samples. The pitches never move, so the pattern stays itself
// while no two passes are the same.
//
// Port of `onStep` in the web app's src/main.ts. The order of the random
// draws is part of the port: gate, then velocity, then — for a sample — the
// detune and the tail scale, all before moving to the next column.

import Foundation

public enum VoiceKind: Sendable {
    case synth
    /// Playback rates per column, from `Music.rateTable`.
    case sample(rates: [Double])
}

public struct StepHit: Sendable, Equatable {
    public let column: Int
    public let velocity: Double
    /// Sample voices only: playback rate with the per-hit detune applied.
    public let rate: Double?
    /// Sample voices only: scales the tail so no two hits ring alike.
    public let releaseScale: Double?

    public init(column: Int, velocity: Double, rate: Double? = nil, releaseScale: Double? = nil) {
        self.column = column
        self.velocity = velocity
        self.rate = rate
        self.releaseScale = releaseScale
    }
}

public enum StepVoicing {
    /// A soft cell fires with probability `base + slope · intensity`, so the
    /// faintest bleed is nearly silent and a near-accent nearly always lands.
    public static let gateBase = 0.35
    public static let gateSlope = 0.65
    public static let velocityLow = 0.72
    public static let velocityHigh = 0.98
    public static let detuneCents = 15.0
    public static let releaseScaleLow = 0.1
    public static let releaseScaleHigh = 0.9

    /// Whether a cell of this intensity fires, given a roll in `[0, 1)`.
    /// Accents are not subject to it at all.
    public static func fires(intensity: Double, roll: Double) -> Bool {
        intensity >= 1 || roll <= gateBase + gateSlope * intensity
    }

    public static func hits(
        step: Int,
        in grid: NoteGrid,
        voice: VoiceKind,
        using random: RandomSource
    ) -> [StepHit] {
        var hits: [StepHit] = []
        hits.reserveCapacity(NoteGrid.columns)

        for column in 0..<NoteGrid.columns {
            let intensity = Double(grid.at(row: step, column: column))
            if intensity <= 0 { continue }
            // An accent costs no roll — matching the web keeps the stream in
            // step, and the stream is what the fixtures are pinned to.
            if intensity < 1, !fires(intensity: intensity, roll: random.next()) { continue }

            let velocity = intensity * random.value(velocityLow, velocityHigh)

            switch voice {
            case .synth:
                hits.append(StepHit(column: column, velocity: velocity))
            case .sample(let rates):
                let cents = random.value(-detuneCents, detuneCents)
                let rate = (rates.indices.contains(column) ? rates[column] : 1)
                    * pow(2, cents / 1200)
                let scale = random.value(releaseScaleLow, releaseScaleHigh)
                hits.append(
                    StepHit(column: column, velocity: velocity, rate: rate, releaseScale: scale))
            }
        }
        return hits
    }
}
