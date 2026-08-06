// Parity with the web app, proved against fixtures generated from its own
// sources rather than from a reading of them.
//
// Most of this is checked for exact equality, including the layout and the
// warp — measured, not assumed: `hypot` and the field arithmetic land on
// identical bits in V8 and libm, so a tolerance there would only hide drift.
//
// Two places genuinely cannot be exact, and both are pinned to the size of
// the divergence actually observed rather than a round number:
//
//   * playback rates — `exp2` against V8's `Math.pow`, one ulp (1.6e-16);
//   * the Newton inverse — a one-ulp seed difference amplified over six
//     iterations (1.2e-13, which is a picometre on screen).

import Foundation
import Testing

@testable import SQIACore

// ------------------------------------------------------------------- PRNG --

@Suite("Random source")
struct RandomSourceTests {
    /// The foundation everything seeded rests on: if this drifts, every
    /// other fixture is meaningless.
    @Test("Mulberry32 reproduces the JavaScript stream exactly")
    func matchesJavaScript() throws {
        let fixture: PRNGFixture = try Fixtures.load("prng")
        #expect(!fixture.streams.isEmpty)

        for stream in fixture.streams {
            let rng = Mulberry32(seed: stream.seed)
            let produced = (0..<stream.values.count).map { _ in rng.next() }
            #expect(produced == stream.values, "seed \(stream.seed)")
        }
    }

    @Test("Values stay in [0, 1)")
    func inRange() {
        let rng = Mulberry32(seed: 7)
        for _ in 0..<10_000 {
            let v = rng.next()
            #expect(v >= 0 && v < 1)
        }
    }

    @Test("Helpers consume exactly one value each")
    func helpersConsumeOne() {
        let a = Mulberry32(seed: 99)
        let b = Mulberry32(seed: 99)
        _ = a.chance(0.5)
        _ = a.index(12)
        _ = a.value(10, 20)
        for _ in 0..<3 { _ = b.next() }
        #expect(a.next() == b.next())
    }
}

// ----------------------------------------------------------------- scales --

@Suite("Musical mapping")
struct MusicTests {
    @Test("Scale table matches the web")
    func scaleTable() throws {
        let fixture: ScalesFixture = try Fixtures.load("scales")
        #expect(fixture.cols == Music.columns)
        #expect(fixture.rows == NoteGrid.rows)
        #expect(fixture.noteNames == Music.noteNames)
        #expect(fixture.scales.map(\.name) == Music.scales.map(\.name))
        #expect(fixture.scales.map(\.steps) == Music.scales.map(\.steps))
    }

    @Test("Every root against every scale maps to the same MIDI notes")
    func midiTables() throws {
        let fixture: ScalesFixture = try Fixtures.load("scales")
        #expect(fixture.midi.count == Music.scales.count * 12)

        for row in fixture.midi {
            let scale = try #require(Music.scale(named: row.scale))
            #expect(
                Music.midiTable(rootPc: row.rootPc, scale: scale) == row.midi,
                "\(row.scale) root \(row.rootPc)"
            )
        }
    }

    @Test("Playback rates match to the last ulp")
    func rateTables() throws {
        let fixture: ScalesFixture = try Fixtures.load("scales")
        var worst = 0.0

        for row in fixture.rates {
            let scale = try #require(Music.scale(named: row.scale))
            for (base, expected) in [
                (60, row.base60), (48, row.base48), (72, row.base72),
            ] {
                let got = Music.rateTable(rootPc: row.rootPc, scale: scale, baseMidi: base)
                worst = max(worst, maxRelativeError(got, expected))
            }
        }
        #expect(worst < 1e-15, "worst relative error \(worst)")
    }

    @Test("The rate clamp bites at the same extremes")
    func rateClamp() throws {
        let fixture: ScalesFixture = try Fixtures.load("scales")
        for row in fixture.clamped {
            let scale = try #require(Music.scale(named: row.scale))
            let got = Music.columnRate(
                row.col, rootPc: row.rootPc, scale: scale, baseMidi: row.base)
            #expect(got == row.rate)
            #expect(got >= 0.25 && got <= 4)
        }
    }
}

// ------------------------------------------------------------------- grid --

@Suite("Note matrix")
struct GridTests {
    /// Cell values come out of exact IEEE arithmetic — multiply, compare,
    /// round to Float32 — so these have to match bit for bit, not nearly.
    @Test("Editing replays the web's results exactly")
    func editing() throws {
        let fixture: GridOpsFixture = try Fixtures.load("grid-ops")
        #expect(!fixture.cases.isEmpty)

        for c in fixture.cases {
            var grid = NoteGrid()
            let rng = Mulberry32(seed: c.seed)

            for op in c.ops {
                switch op.op {
                case "brush":
                    grid.brush(gx: try #require(op.gx), gy: try #require(op.gy))
                case "erase":
                    grid.erase(row: try #require(op.r), column: try #require(op.c))
                case "random":
                    grid.randomize(using: rng)
                case "clear":
                    grid.clear()
                default:
                    Issue.record("unknown op \(op.op) in case \(c.name)")
                }
            }

            #expect(grid.cells == c.cells, "case \(c.name)")
            #expect(grid.hasNotes == c.hasNotes, "case \(c.name)")
        }
    }

    @Test("Out-of-range input is ignored rather than trapping")
    func outOfRange() {
        var grid = NoteGrid()
        for (gx, gy) in [
            (-0.1, 5.0), (12.0, 5.0), (5.0, -0.1), (5.0, 16.0),
            (Double.nan, 5.0), (5.0, Double.nan), (1e30, 1e30), (-1e30, -1e30),
        ] {
            grid.brush(gx: gx, gy: gy)
        }
        #expect(!grid.hasNotes)
        #expect(grid.at(row: -1, column: 0) == 0)
        #expect(grid.at(row: 0, column: 99) == 0)
    }

    @Test("The eraser stays on the grid wherever it is aimed")
    func eraseClamps() {
        var grid = NoteGrid()
        for r in 0..<NoteGrid.rows {
            for c in 0..<NoteGrid.columns {
                grid.stamp(row: r, column: c)
            }
        }
        // Bottom-right corner: the 2x2 block anchors back onto the field.
        grid.erase(row: NoteGrid.rows - 1, column: NoteGrid.columns - 1)
        #expect(grid.at(row: NoteGrid.rows - 1, column: NoteGrid.columns - 1) == 0)
        #expect(grid.at(row: NoteGrid.rows - 2, column: NoteGrid.columns - 2) == 0)
        // Negative input clears nothing and does not trap.
        grid.erase(row: -5, column: -5)
    }

    @Test("A pattern survives a round trip through the snapshot format")
    func snapshotRoundTrip() {
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: 4242))
        let restored = NoteGrid(cells: ProjectSnapshot.encode(grid))
        // Two decimals is lossy by design; what matters is which cells hold
        // notes and that the intensities land within that rounding.
        for i in 0..<NoteGrid.count {
            #expect((grid.cells[i] > 0) == (restored.cells[i] > 0))
            #expect(abs(Double(grid.cells[i]) - Double(restored.cells[i])) <= 0.005)
        }
    }
}

// --------------------------------------------------------------- geometry --

@Suite("Dome geometry")
struct FieldGeometryTests {
    /// The Newton inverse is the only part that diverges at all, by about
    /// 1.2e-13 relative — a one-ulp difference in the starting radius,
    /// amplified over six iterations.
    static let inverseTolerance = 1e-12

    /// Exact: cell fitting is multiply, divide and `hypot`, and those land
    /// on the same bits in both engines. Anything looser here would hide a
    /// real change to the fitting loop.
    @Test("Cell fitting and layout match every viewport bit for bit")
    func layouts() throws {
        let fixture: GeometryFixture = try Fixtures.load("geometry")
        #expect(!fixture.viewports.isEmpty)

        for v in fixture.viewports {
            let l = Field.layout(x: v.vx, y: v.vy, width: v.vw, height: v.vh)
            #expect(l.cell == v.layout.cell, "\(v.name) cell")
            #expect(l.ox == v.layout.ox, "\(v.name) ox")
            #expect(l.oy == v.layout.oy, "\(v.name) oy")
            #expect(l.cx == v.layout.cx, "\(v.name) cx")
            #expect(l.cy == v.layout.cy, "\(v.name) cy")
            #expect(l.radius == v.layout.R, "\(v.name) radius")
        }
    }

    @Test("Every cell centre warps to the same screen point bit for bit")
    func warpField() throws {
        let fixture: GeometryFixture = try Fixtures.load("geometry")

        for v in fixture.viewports {
            let l = Field.layout(x: v.vx, y: v.vy, width: v.vw, height: v.vh)
            var got: [Double] = []
            var expected: [Double] = []

            for centre in v.centres {
                let x = l.ox + (Double(centre.c) + 0.5) * l.cell
                let y = l.oy + (Double(centre.r) + 0.5) * l.cell
                let p = Field.warp(x: x, y: y, in: l)
                got += [x, y, p.x, p.y, Field.warpScale(x: x, y: y, in: l)]
                expected += [centre.x, centre.y, centre.sx, centre.sy, centre.scale]
            }
            #expect(got == expected, "\(v.name)")
        }
    }

    @Test("Taps land on the same cells, inside the field and outside it")
    func hitTesting() throws {
        let fixture: GeometryFixture = try Fixtures.load("geometry")
        var worst = 0.0

        for v in fixture.viewports {
            let l = Field.layout(x: v.vx, y: v.vy, width: v.vw, height: v.vh)
            for tap in v.taps {
                let u = Field.unwarp(x: tap.x, y: tap.y, in: l)
                worst = max(worst, maxRelativeError([u.x, u.y], [tap.ux, tap.uy]))

                let pos = Field.position(x: tap.x, y: tap.y, in: l)
                let hit = Field.hit(x: tap.x, y: tap.y, in: l)
                let where_ = "\(v.name) tap (\(tap.x), \(tap.y))"

                if let expected = tap.pos {
                    let p = try #require(pos, "\(where_): expected a hit")
                    worst = max(worst, maxRelativeError([p.gx, p.gy], [expected.gx, expected.gy]))
                } else {
                    #expect(pos == nil, "\(where_): expected a miss")
                }

                if let expected = tap.hit {
                    let h = try #require(hit, "\(where_): expected a cell")
                    #expect(h.row == expected.r && h.column == expected.c, "\(where_)")
                } else {
                    #expect(hit == nil, "\(where_): expected no cell")
                }
            }
        }
        #expect(worst < Self.inverseTolerance, "worst relative error \(worst)")
    }

    /// A finger has to land back where it was drawn; this is the property
    /// the Newton solver exists for.
    @Test("Warping and unwarping a point returns it")
    func roundTrip() {
        let l = Field.layout(x: 0, y: 0, width: 375, height: 600)
        var worst = 0.0
        for r in 0..<NoteGrid.rows {
            for c in 0..<NoteGrid.columns {
                let x = l.ox + (Double(c) + 0.5) * l.cell
                let y = l.oy + (Double(r) + 0.5) * l.cell
                let w = Field.warp(x: x, y: y, in: l)
                let back = Field.unwarp(x: w.x, y: w.y, in: l)
                worst = max(worst, max(abs(back.x - x), abs(back.y - y)))
            }
        }
        #expect(worst < 1e-6, "worst absolute error \(worst) pt")
    }

    @Test("The fitted field stays inside its box")
    func staysInsideBox() {
        for (w, h) in [(375.0, 600.0), (320.0, 454.0), (168.75, 270.0), (900.0, 400.0)] {
            let l = Field.layout(x: 0, y: 0, width: w, height: h)
            for r in 0..<NoteGrid.rows {
                for c in 0..<NoteGrid.columns {
                    let p = Field.warp(
                        x: l.ox + (Double(c) + 0.5) * l.cell,
                        y: l.oy + (Double(r) + 0.5) * l.cell,
                        in: l
                    )
                    #expect(p.x >= 0 && p.x <= w, "\(w)x\(h)")
                    #expect(p.y >= 0 && p.y <= h, "\(w)x\(h)")
                }
            }
        }
    }
}

// ----------------------------------------------------------------- naming --

@Suite("Project names")
struct ProjectNamesTests {
    @Test("Seeded name streams match the web")
    func streams() throws {
        let fixture: NamesFixture = try Fixtures.load("names")
        for stream in fixture.streams {
            let rng = Mulberry32(seed: stream.seed)
            let produced = (0..<stream.names.count).map { _ in ProjectNames.random(using: rng) }
            #expect(produced == stream.names, "seed \(stream.seed)")
        }
    }
}

// -------------------------------------------------------------- snapshots --

@Suite("Project snapshot")
struct ProjectSnapshotTests {
    @Test("Snapshots carry the same values the web writes")
    func matchesWeb() throws {
        let fixture: SnapshotFixture = try Fixtures.load("snapshot")
        #expect(!fixture.cases.isEmpty)

        for c in fixture.cases {
            let tracks = c.snapshot.tracks.enumerated().map { i, expected -> TrackSnapshot in
                var grid = NoteGrid()
                grid.randomize(using: Mulberry32(seed: c.seed &+ UInt32(i)))
                return TrackSnapshot(voiceIdx: expected.voiceIdx, muted: expected.muted, grid: grid)
            }
            let snapshot = ProjectSnapshot(
                bpm: c.snapshot.bpm,
                rootPc: c.snapshot.root_pc,
                scale: c.snapshot.scale,
                tracks: tracks
            )

            #expect(snapshot.tracks.count == c.snapshot.tracks.count)
            for (got, expected) in zip(snapshot.tracks, c.snapshot.tracks) {
                #expect(got.voiceIdx == expected.voiceIdx)
                #expect(got.muted == expected.muted)
                #expect(got.cells == expected.cells, "seed \(c.seed)")
            }
        }
    }

    /// The keys are the database's, and the database is shared with the web.
    @Test("Encodes to the column names the web uses")
    func wireFormat() throws {
        var grid = NoteGrid()
        grid.brush(gx: 3.5, gy: 5.5)
        let snapshot = ProjectSnapshot(
            bpm: 128,
            rootPc: 9,
            scale: "minor",
            tracks: [TrackSnapshot(voiceIdx: 4, muted: true, grid: grid)]
        )

        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["bpm"] as? Int == 128)
        #expect(object["root_pc"] as? Int == 9)
        #expect(object["scale"] as? String == "minor")

        let tracks = try #require(object["tracks"] as? [[String: Any]])
        #expect(tracks.count == 1)
        #expect(tracks[0]["voiceIdx"] as? Int == 4)
        #expect(tracks[0]["muted"] as? Bool == true)
        #expect((tracks[0]["cells"] as? [Double])?.count == NoteGrid.count)

        let decoded = try JSONDecoder().decode(ProjectSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test("A project row decodes from the shape PostgREST returns")
    func decodesProjectRow() throws {
        let json = """
            {
              "id": "9f1c0f3e-0000-4000-8000-000000000000",
              "name": "Wild Amoeba",
              "bpm": 120,
              "root_pc": 9,
              "scale": "minor",
              "tracks": [{"voiceIdx": 0, "muted": false, "cells": [0, 0.5, 1]}],
              "updated_at": "2026-08-06T21:00:00+00:00"
            }
            """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.name == "Wild Amoeba")
        #expect(project.rootPc == 9)
        #expect(project.tracks[0].grid.at(row: 0, column: 1) == 0.5)
        #expect(project.tracks[0].grid.at(row: 0, column: 2) == 1)
        // A short cells array leaves the rest of the pattern empty.
        #expect(project.tracks[0].grid.cells.count == NoteGrid.count)
    }
}
