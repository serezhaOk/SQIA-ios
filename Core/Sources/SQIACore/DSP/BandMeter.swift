// How loud the output is, band by band — what the mixer's wave is drawn from.
//
// Nine band-passes across what the ear hears of the mix, spaced evenly in
// octaves from 60 Hz to 10 kHz, one per bar of the wave: a kick lifts the
// left of it, a hat the right. Each is the trapezoidal state-variable
// filter, which stays stable right up the band where the simpler one runs
// away at a phone's sample rate.
//
// It only measures. The render thread feeds it the finished mono sum and
// asks for a block's worth of levels; nothing it does reaches the sound.

import Foundation

public struct BandMeter: Sendable {
    public static let bands = 9
    public static let lowest = 60.0
    public static let highest = 10_000.0
    /// Wide enough that neighbouring bands overlap and a tone between two
    /// centres still moves both.
    static let q = 1.4

    private var a1: [Double]
    private var a2: [Double]
    private var a3: [Double]
    private var ic1: [Double]
    private var ic2: [Double]
    /// Energy since the last read, per band.
    private var energy: [Double]
    private var counted = 0

    public init(sampleRate: Double) {
        let k = 1 / Self.q
        var a1 = [Double](), a2 = [Double](), a3 = [Double]()
        for band in 0..<Self.bands {
            let centre = min(Self.centre(band), sampleRate * 0.45)
            let g = tan(Double.pi * centre / sampleRate)
            let first = 1 / (1 + g * (g + k))
            a1.append(first)
            a2.append(g * first)
            a3.append(g * g * first)
        }
        self.a1 = a1
        self.a2 = a2
        self.a3 = a3
        ic1 = Array(repeating: 0, count: Self.bands)
        ic2 = Array(repeating: 0, count: Self.bands)
        energy = Array(repeating: 0, count: Self.bands)
    }

    /// Band `index`'s centre, in hertz.
    public static func centre(_ index: Int) -> Double {
        lowest * pow(highest / lowest, Double(index) / Double(bands - 1))
    }

    public mutating func process(_ sample: Double) {
        for b in 0..<Self.bands {
            let v3 = sample - ic2[b]
            let v1 = a1[b] * ic1[b] + a2[b] * v3
            let v2 = ic2[b] + a2[b] * ic1[b] + a3[b] * v3
            ic1[b] = 2 * v1 - ic1[b]
            ic2[b] = 2 * v2 - ic2[b]
            energy[b] += v1 * v1
        }
        counted += 1
    }

    /// Silence, without running the filters over it: what a block the
    /// mixer skipped still counts toward the average.
    public mutating func skip(_ frames: Int) {
        counted += frames
    }

    /// Each band's RMS since the last read, and start again. `into` is
    /// written in place, so the render thread never allocates.
    public mutating func read(into levels: inout [Double]) {
        let n = Double(max(counted, 1))
        for b in 0..<Self.bands {
            levels[b] = (energy[b] / n).squareRoot()
            energy[b] = 0
        }
        counted = 0
    }

    public mutating func clear() {
        for b in 0..<Self.bands {
            ic1[b] = 0
            ic2[b] = 0
            energy[b] = 0
        }
        counted = 0
    }
}
