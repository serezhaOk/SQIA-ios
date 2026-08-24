// The field, compared with the web primitive for primitive.
//
// The fixture is not a description of what the web draws — it is what the
// web drew, captured by standing a recorder in for its 2D context. So these
// replay the same flashes over the same frames and check every dot, halo and
// streak that comes out: position, size, colour and alpha.

import Foundation
import Testing

@testable import SQIACore

struct FieldFixture: Decodable {
    struct Viewport: Decodable {
        let vx: Double
        let vy: Double
        let vw: Double
        let vh: Double
    }
    struct Op: Decodable {
        let op: String
        let x: Double
        let y: Double
        let x0: Double?
        let y0: Double?
        let x1: Double?
        let y1: Double?
        let radius: Double?
        let width: Double?
        let height: Double?
        let r: Double
        let g: Double
        let b: Double
        let alpha: Double

        enum CodingKeys: String, CodingKey {
            case op, x, y, x0, y0, x1, y1, radius, width, height, r, g, b, alpha
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            op = try c.decode(String.self, forKey: .op)
            x0 = try c.decodeIfPresent(Double.self, forKey: .x0)
            y0 = try c.decodeIfPresent(Double.self, forKey: .y0)
            // A streak records its start as x0/y0; everything else uses x/y.
            x = try c.decodeIfPresent(Double.self, forKey: .x) ?? x0 ?? 0
            y = try c.decodeIfPresent(Double.self, forKey: .y) ?? y0 ?? 0
            x1 = try c.decodeIfPresent(Double.self, forKey: .x1)
            y1 = try c.decodeIfPresent(Double.self, forKey: .y1)
            radius = try c.decodeIfPresent(Double.self, forKey: .radius)
            width = try c.decodeIfPresent(Double.self, forKey: .width)
            height = try c.decodeIfPresent(Double.self, forKey: .height)
            r = try c.decode(Double.self, forKey: .r)
            g = try c.decode(Double.self, forKey: .g)
            b = try c.decode(Double.self, forKey: .b)
            alpha = try c.decode(Double.self, forKey: .alpha)
        }
    }
    struct Case: Decodable {
        let name: String
        let seed: UInt32
        let viewport: Viewport
        let frames: Int
        let dt: Double
        let playhead: Int
        let detail: Double
        let alpha: Double
        /// row, column, velocity, frame
        let flashes: [[Double]]
        let cells: [Float]
        let ops: [Op]
    }
    let cases: [Case]
}

@Suite("Field")
struct FieldTests {
    /// Everything here is multiply, add and the odd `exp`/`sin`, so the two
    /// platforms land within a whisker of each other; this is the size of
    /// the gap actually observed, not a comfortable round number.
    static let tolerance = 1e-9

    private func replay(_ c: FieldFixture.Case) -> (NoteGrid, [FieldDraw]) {
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: c.seed))

        let animator = FieldAnimator()
        let layout = Field.layout(
            x: c.viewport.vx, y: c.viewport.vy,
            width: c.viewport.vw, height: c.viewport.vh)

        var draws: [FieldDraw] = []
        for frame in 0..<c.frames {
            for flash in c.flashes where Int(flash.count > 3 ? flash[3] : 0) == frame {
                animator.flash(
                    row: Int(flash[0]), column: Int(flash[1]), velocity: flash[2])
            }
            animator.advance(by: c.dt)
            animator.draws(
                grid: grid, layout: layout, playhead: c.playhead,
                detail: c.detail, alpha: c.alpha, into: &draws)
        }
        return (grid, draws)
    }

    @Test("Every primitive matches the web, in the same order")
    func matchesTheWeb() throws {
        let fixture: FieldFixture = try Fixtures.load("field")
        #expect(!fixture.cases.isEmpty)

        for c in fixture.cases {
            let (grid, draws) = replay(c)

            // The pattern itself has to line up first, or nothing else means
            // anything.
            #expect(grid.cells == c.cells, "\(c.name): pattern")
            #expect(draws.count == c.ops.count, "\(c.name): primitive count")
            if draws.count != c.ops.count { continue }

            var worst = 0.0
            for (i, (got, expected)) in zip(draws, c.ops).enumerated() {
                let where_ = "\(c.name) op \(i)"

                let kind: String
                switch got.kind {
                case .dot: kind = "dot"
                case .glow: kind = "glow"
                case .streak: kind = "streak"
                // The web sums nothing, so a fixture can never ask for one.
                case .source: kind = "source"
                }
                #expect(kind == expected.op, "\(where_): kind")
                if kind != expected.op { break }

                // Colour is an integer on both sides — no tolerance for it.
                #expect(got.color.red == expected.r, "\(where_): red")
                #expect(got.color.green == expected.g, "\(where_): green")
                #expect(got.color.blue == expected.b, "\(where_): blue")

                var mine = [got.x, got.y, got.alpha]
                var theirs = [expected.x, expected.y, expected.alpha]
                switch got.kind {
                case .dot:
                    mine.append(got.size)
                    theirs.append(expected.radius ?? .nan)
                case .glow:
                    mine += [got.size, got.size]
                    theirs += [expected.width ?? .nan, expected.height ?? .nan]
                case .streak:
                    mine += [got.x1, got.y1, got.size]
                    theirs += [expected.x1 ?? .nan, expected.y1 ?? .nan, expected.width ?? .nan]
                case .source:
                    Issue.record("\(where_): the web draws no field sources")
                }
                worst = max(worst, maxRelativeError(mine, theirs))
            }
            #expect(worst < Self.tolerance, "\(c.name): worst relative error \(worst)")
        }
    }

    @Test("A fresh field draws one dot per cell and nothing else")
    func atRestIsJustDots() {
        let animator = FieldAnimator()
        let layout = Field.layout(x: 0, y: 0, width: 375, height: 600)
        animator.advance(by: 1 / 60)
        let draws = animator.draws(grid: NoteGrid(), layout: layout, playhead: -1)

        #expect(draws.count == NoteGrid.count)
        #expect(draws.allSatisfy { $0.kind == .dot })
        #expect(draws.allSatisfy { $0.color == .white })
    }

    @Test("The playhead row is brighter than the rest")
    func playheadLifts() {
        let animator = FieldAnimator()
        let layout = Field.layout(x: 0, y: 0, width: 375, height: 600)
        animator.advance(by: 1 / 60)
        let draws = animator.draws(grid: NoteGrid(), layout: layout, playhead: 4)

        let onHead = draws[(4 * NoteGrid.columns)..<(5 * NoteGrid.columns)]
        let elsewhere = draws[0..<NoteGrid.columns]
        #expect(onHead.map(\.alpha).min()! > elsewhere.map(\.alpha).max()!)
    }

    @Test("A flash decays away and takes its ripple with it")
    func flashDecays() {
        let animator = FieldAnimator()
        animator.flash(row: 5, column: 6, velocity: 1)
        #expect(animator.energy[5 * NoteGrid.columns + 6] == 1)
        #expect(animator.activeWaveCount == 1)

        // The ripple outlives the bloom, but not by much.
        for _ in 0..<Int(FieldAnimator.waveLife * 60) + 2 {
            animator.advance(by: 1 / 60)
        }
        #expect(animator.activeWaveCount == 0)

        for _ in 0..<180 { animator.advance(by: 1 / 60) }
        #expect(animator.energy.allSatisfy { $0 == 0 })
    }

    @Test("Ripples are capped so a wall of notes cannot pile them up")
    func waveBudget() {
        let animator = FieldAnimator()
        for i in 0..<200 {
            animator.flash(row: i % NoteGrid.rows, column: i % NoteGrid.columns, velocity: 1)
        }
        #expect(animator.activeWaveCount == FieldAnimator.maxWaves)
    }

    @Test("The colour cycle steps rather than blends")
    func waveColourSteps() {
        #expect(FieldAnimator.waveColor(phase: 0) == FieldAnimator.waveStops[0])
        #expect(FieldAnimator.waveColor(phase: 0.32) == FieldAnimator.waveStops[0])
        #expect(FieldAnimator.waveColor(phase: 0.34) == FieldAnimator.waveStops[1])
        #expect(FieldAnimator.waveColor(phase: 0.99) == FieldAnimator.waveStops[2])
        // Out of range clamps rather than crashing.
        #expect(FieldAnimator.waveColor(phase: 1.5) == FieldAnimator.waveStops[2])
        #expect(FieldAnimator.waveColor(phase: -1) == FieldAnimator.waveStops[0])
    }

    @Test("A faded-out field draws nothing at all")
    func invisibleFieldIsFree() {
        let animator = FieldAnimator()
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: 1))
        animator.flash(row: 0, column: 0, velocity: 1)
        animator.advance(by: 1 / 60)

        let layout = Field.layout(x: 0, y: 0, width: 375, height: 600)
        #expect(animator.draws(grid: grid, layout: layout, playhead: 0, alpha: 0).isEmpty)
        #expect(animator.draws(grid: grid, layout: layout, playhead: 0, alpha: 0.005).isEmpty)
    }

    @Test("Thumbnails skip the expensive extras")
    func lowDetailSkipsStreaks() {
        let animator = FieldAnimator()
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: 1))
        animator.flash(row: 0, column: 0, velocity: 1)
        animator.advance(by: 1 / 60)
        let layout = Field.layout(x: 0, y: 0, width: 169, height: 270)

        let full = animator.draws(grid: grid, layout: layout, playhead: 0, detail: 1)
        let thumb = animator.draws(grid: grid, layout: layout, playhead: 0, detail: 0.4)
        #expect(full.contains { $0.kind == .streak })
        #expect(!thumb.contains { $0.kind == .streak })
    }

    @Test("Resetting puts the field back to rest")
    func resetting() {
        let animator = FieldAnimator()
        animator.flash(row: 3, column: 3, velocity: 1)
        animator.advance(by: 1 / 60)
        animator.reset()
        #expect(animator.activeWaveCount == 0)
        #expect(animator.energy.allSatisfy { $0 == 0 })
    }

    // ---------------------------------------------------------- heat style --

    /// Drawing goes out through `warp` and a finger comes back through
    /// `unwarp`. If those two ever stop agreeing about the dome, painting
    /// lands in a cell next to the one under the finger — which looks like a
    /// gesture bug rather than a geometry one, and is close enough to right
    /// that it is easy to miss on a screen.
    @Test("A flat field puts a finger in the cell it is over")
    func flatRoundTrip() {
        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700, style: .heat)

        for row in 0..<NoteGrid.rows {
            for column in 0..<NoteGrid.columns {
                let x = layout.ox + (Double(column) + 0.5) * layout.cell
                let y = layout.oy + (Double(row) + 0.5) * layout.cell

                let drawn = Field.warp(x: x, y: y, in: layout)
                #expect(drawn.x == x, "row \(row) column \(column): x moved")
                #expect(drawn.y == y, "row \(row) column \(column): y moved")

                let hit = Field.hit(x: drawn.x, y: drawn.y, in: layout)
                #expect(hit?.row == row, "row \(row) column \(column): row")
                #expect(hit?.column == column, "row \(row) column \(column): column")
            }
        }
    }

    @Test("A flat field fills the box it is given")
    func flatFitsTheBox() {
        // The dome pushes dots outward, so the classic fit shaves the cell to
        // make room. Flat, nothing overflows and nothing needs shaving.
        let flat = Field.fitCell(width: 393, height: 700, style: .heat)
        let classic = Field.fitCell(width: 393, height: 700, style: .classic)
        #expect(flat == min(393 / Double(NoteGrid.columns), 700 / Double(NoteGrid.rows)))
        #expect(classic < flat)
    }

    @Test("Only a drawn note is a source")
    func onlyNotesAreSources() {
        let animator = FieldAnimator()
        var grid = NoteGrid()
        grid.stamp(row: 2, column: 3)
        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700, style: .heat)
        let draws = animator.draws(grid: grid, layout: layout, playhead: -1)

        let sources = draws.filter { $0.kind == .source }
        let lit = grid.cells.filter { $0 > 0 }.count
        #expect(sources.count == lit)
        #expect(sources.count > 0)

        // Everything else on screen is the resting grid, and nothing in the
        // heat style draws a halo or a streak of its own — the shape comes
        // out of the sum.
        #expect(!draws.contains { $0.kind == .glow || $0.kind == .streak })
        #expect(draws.filter { $0.kind == .dot }.count == NoteGrid.count - lit)
    }

    @Test("Neighbouring sources reach far enough to close up")
    func neighboursOverlap() {
        let animator = FieldAnimator()
        var grid = NoteGrid()
        grid.stamp(row: 5, column: 5)
        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700, style: .heat)
        let sources = animator.draws(grid: grid, layout: layout, playhead: -1)
            .filter { $0.kind == .source }
            .sorted { $0.x < $1.x }

        // Two sources a cell apart have to overlap, or a stroke would read as
        // a row of separate circles instead of one shape. Their radii sum has
        // to beat the gap between them.
        #expect(sources.count >= 2)
        for (a, b) in zip(sources, sources.dropFirst()) {
            let gap = hypot(b.x - a.x, b.y - a.y)
            if gap > layout.cell * 1.5 { continue }
            #expect(a.size + b.size > gap, "sources \(gap) apart do not reach each other")
        }
    }

    @Test("A struck source carries its own heat")
    func struckSourcesCarryEnergy() {
        let animator = FieldAnimator()
        var grid = NoteGrid()
        grid.stamp(row: 5, column: 5)
        grid.stamp(row: 12, column: 2)
        animator.flash(row: 5, column: 5, velocity: 1)
        animator.advance(by: 1 / 60)

        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700, style: .heat)
        let sources = animator.draws(grid: grid, layout: layout, playhead: 5)
            .filter { $0.kind == .source }

        // The struck cell is hot and leans harder on the sum; the one across
        // the grid is untouched, so the ripple stays where the note landed.
        #expect(sources.contains { $0.energy > 0.5 })
        #expect(sources.contains { $0.energy == 0 })
    }

    /// The dot field blinks; the heat field spreads. Two very different
    /// lengths of time, off one flash.
    @Test("The heat field's flash outlives the dot field's")
    func bloomOutlastsEnergy() {
        let animator = FieldAnimator()
        animator.flash(row: 4, column: 4, velocity: 1)
        for _ in 0..<60 { animator.advance(by: 1 / 60) }

        let i = 4 * NoteGrid.columns + 4
        // A second on, the dot field has all but forgotten the note and the
        // heat field is still better than a third lit.
        #expect(Double(animator.bloom[i]) > 0.3)
        #expect(Double(animator.bloom[i]) > 5 * Double(animator.energy[i]))
    }

    @Test("Resetting clears the slow reading too")
    func resettingClearsBloom() {
        let animator = FieldAnimator()
        animator.flash(row: 4, column: 4, velocity: 1)
        animator.advance(by: 1 / 60)
        animator.reset()
        #expect(animator.bloom.allSatisfy { $0 == 0 })
    }

    /// A grid of dots all one size reads as a weight sitting on the screen.
    @Test("The resting grid tapers toward the rim")
    func restingGridTapers() {
        let animator = FieldAnimator()
        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700, style: .heat)
        let dots = animator.draws(grid: NoteGrid(), layout: layout, playhead: -1)
        #expect(dots.count == NoteGrid.count)

        // Row-major, one dot per cell on an empty grid.
        let corner = dots[0]
        let middle = dots[8 * NoteGrid.columns + 6]
        #expect(corner.size < middle.size)

        // The breathing is a ±14% wobble and the taper is far wider than
        // that, so no cell near the rim can out-measure one near the middle.
        let rim = dots[(NoteGrid.rows - 1) * NoteGrid.columns + NoteGrid.columns - 1]
        #expect(rim.size < middle.size)
    }

    @Test("The classic field sums nothing")
    func classicHasNoSources() {
        let animator = FieldAnimator()
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: 1))
        animator.flash(row: 0, column: 0, velocity: 1)
        animator.advance(by: 1 / 60)

        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700)
        #expect(!animator.draws(grid: grid, layout: layout, playhead: 0).contains {
            $0.kind == .source
        })
    }
}
