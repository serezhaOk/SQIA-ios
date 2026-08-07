// "Random within the frame": the rule that keeps a pattern recognisable
// while never repeating it exactly.
//
// There is no fixture for this one — the web's onStep is a closure over a
// live AudioContext and a canvas, so the generator cannot sample it. These
// check the behaviour the web code specifies, and the audible result is what
// the A/B pass covers.

import Foundation
import Testing

@testable import SQIACore

@Suite("Step voicing")
struct StepVoicingTests {
    @Test("An accent always fires, however the dice fall")
    func accentsAlwaysFire() {
        var g = NoteGrid()
        g.brush(gx: 3.5, gy: 5.5)  // dead centre: a single full-intensity cell
        #expect(g.at(row: 5, column: 3) == 1)

        for seed in UInt32(0)..<200 {
            let hits = StepVoicing.hits(
                step: 5, in: g, voice: .synth, using: Mulberry32(seed: seed))
            #expect(hits.count == 1)
            #expect(hits[0].column == 3)
        }
    }

    @Test("Empty cells never fire and cost no randomness")
    func emptyCellsAreFree() {
        let g = NoteGrid()
        let rng = Mulberry32(seed: 1)
        let reference = Mulberry32(seed: 1)
        #expect(StepVoicing.hits(step: 0, in: g, voice: .synth, using: rng).isEmpty)
        #expect(rng.next() == reference.next())
    }

    @Test("A soft cell fires about as often as its brightness says")
    func softGateProbability() {
        // The brush leaves a 0.756 neighbour beside a full cell; its gate is
        // 0.35 + 0.65 × 0.756 ≈ 0.841.
        var g = NoteGrid()
        g.brush(gx: 3.92, gy: 5.08)
        let intensity = Double(g.at(row: 5, column: 4))
        #expect(abs(intensity - 0.756) < 1e-3)

        let expected = StepVoicing.gateBase + StepVoicing.gateSlope * intensity
        let rng = Mulberry32(seed: 4242)
        var fired = 0
        let trials = 20_000
        for _ in 0..<trials where StepVoicing.fires(intensity: intensity, roll: rng.next()) {
            fired += 1
        }
        let observed = Double(fired) / Double(trials)
        #expect(abs(observed - expected) < 0.02, "fired \(observed), expected \(expected)")
    }

    @Test("The faintest cells are nearly silent and the brightest nearly certain")
    func gateEndpoints() {
        #expect(StepVoicing.fires(intensity: 1, roll: 0.999))  // accents ignore the roll
        #expect(!StepVoicing.fires(intensity: 0.1, roll: 0.9))
        #expect(StepVoicing.fires(intensity: 0.99, roll: 0.5))
    }

    @Test("Velocity shimmers within a tight band below the cell's intensity")
    func velocityRange() {
        var g = NoteGrid()
        for column in 0..<NoteGrid.columns {
            g.brush(gx: Double(column) + 0.5, gy: 2.5)
        }
        let rng = Mulberry32(seed: 77)
        for _ in 0..<200 {
            for hit in StepVoicing.hits(step: 2, in: g, voice: .synth, using: rng) {
                #expect(hit.velocity >= StepVoicing.velocityLow)
                #expect(hit.velocity <= StepVoicing.velocityHigh)
            }
        }
    }

    @Test("A sample hit is detuned by at most fifteen cents")
    func sampleDetune() throws {
        var g = NoteGrid()
        g.brush(gx: 0.5, gy: 0.5)
        let rates = Music.rateTable(rootPc: 9, scale: Music.scales[0])
        let rng = Mulberry32(seed: 9)

        let limit = pow(2, StepVoicing.detuneCents / 1200)
        for _ in 0..<500 {
            let hits = StepVoicing.hits(
                step: 0, in: g, voice: .sample(rates: rates), using: rng)
            let hit = try #require(hits.first)
            let ratio = try #require(hit.rate) / rates[0]
            #expect(ratio >= 1 / limit - 1e-9 && ratio <= limit + 1e-9)

            let scale = try #require(hit.releaseScale)
            #expect(scale >= StepVoicing.releaseScaleLow && scale <= StepVoicing.releaseScaleHigh)
        }
    }

    @Test("Synth hits carry no sample fields")
    func synthHitsAreBare() {
        var g = NoteGrid()
        g.brush(gx: 2.5, gy: 1.5)
        let hits = StepVoicing.hits(step: 1, in: g, voice: .synth, using: Mulberry32(seed: 3))
        #expect(hits.first?.rate == nil)
        #expect(hits.first?.releaseScale == nil)
    }

    /// The order of the draws is part of the port: a synth accent takes one
    /// value, a sample accent takes three.
    @Test("Each voice kind consumes the stream the web consumes")
    func randomnessBudget() {
        var g = NoteGrid()
        g.brush(gx: 5.5, gy: 0.5)  // one accent, no soft neighbours

        let synthRng = Mulberry32(seed: 11)
        _ = StepVoicing.hits(step: 0, in: g, voice: .synth, using: synthRng)
        let synthReference = Mulberry32(seed: 11)
        _ = synthReference.next()
        #expect(synthRng.next() == synthReference.next())

        let rates = Music.rateTable(rootPc: 0, scale: Music.scales[0])
        let sampleRng = Mulberry32(seed: 11)
        _ = StepVoicing.hits(step: 0, in: g, voice: .sample(rates: rates), using: sampleRng)
        let sampleReference = Mulberry32(seed: 11)
        for _ in 0..<3 { _ = sampleReference.next() }
        #expect(sampleRng.next() == sampleReference.next())
    }

    @Test("Hits come out in column order")
    func columnOrder() {
        var g = NoteGrid()
        for column in stride(from: 0, to: NoteGrid.columns, by: 3) {
            g.brush(gx: Double(column) + 0.5, gy: 7.5)
        }
        let hits = StepVoicing.hits(step: 7, in: g, voice: .synth, using: Mulberry32(seed: 5))
        #expect(hits.map(\.column) == hits.map(\.column).sorted())
    }
}
