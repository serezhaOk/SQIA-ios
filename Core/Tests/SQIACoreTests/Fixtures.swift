// Loading the golden fixtures, and the shapes they decode into.
//
// The JSON is produced by tools/gen-fixtures, which runs the actual web
// sources. Regenerate with `node --run gen` in that directory whenever the
// web app's behaviour changes on purpose.

import Foundation
import Testing

enum Fixtures {
    struct MissingFixture: Error, CustomStringConvertible {
        let name: String
        var description: String {
            "fixture \(name).json is missing — run `node --run gen` in tools/gen-fixtures"
        }
    }

    static func load<T: Decodable>(_ name: String, as: T.Type = T.self) throws -> T {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else {
            throw MissingFixture(name: name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

// ---------------------------------------------------------------- payloads --

struct PRNGFixture: Decodable {
    struct Stream: Decodable {
        let seed: UInt32
        let values: [Double]
    }
    let streams: [Stream]
}

struct ScalesFixture: Decodable {
    struct ScaleDef: Decodable {
        let name: String
        let steps: [Int]
    }
    struct MidiRow: Decodable {
        let scale: String
        let rootPc: Int
        let midi: [Int]
    }
    struct RateRow: Decodable {
        let scale: String
        let rootPc: Int
        let base60: [Double]
        let base48: [Double]
        let base72: [Double]
    }
    struct ClampRow: Decodable {
        let col: Int
        let rootPc: Int
        let scale: String
        let base: Int
        let rate: Double
    }
    let cols: Int
    let rows: Int
    let noteNames: [String]
    let scales: [ScaleDef]
    let midi: [MidiRow]
    let rates: [RateRow]
    let clamped: [ClampRow]
}

struct GridOpsFixture: Decodable {
    struct Op: Decodable {
        let op: String
        let gx: Double?
        let gy: Double?
        let r: Int?
        let c: Int?
    }
    struct Case: Decodable {
        let name: String
        let seed: UInt32
        let ops: [Op]
        let cells: [Float]
        let hasNotes: Bool
    }
    let cases: [Case]
}

struct GeometryFixture: Decodable {
    struct Layout: Decodable {
        let cell: Double
        let ox: Double
        let oy: Double
        let cx: Double
        let cy: Double
        let R: Double
    }
    struct Centre: Decodable {
        let r: Int
        let c: Int
        let x: Double
        let y: Double
        let sx: Double
        let sy: Double
        let scale: Double
    }
    struct Position: Decodable {
        let gx: Double
        let gy: Double
    }
    struct Cell: Decodable {
        let r: Int
        let c: Int
    }
    struct Tap: Decodable {
        let x: Double
        let y: Double
        let ux: Double
        let uy: Double
        let pos: Position?
        let hit: Cell?
    }
    struct Viewport: Decodable {
        let name: String
        let vx: Double
        let vy: Double
        let vw: Double
        let vh: Double
        let layout: Layout
        let centres: [Centre]
        let taps: [Tap]
    }
    let viewports: [Viewport]
}

struct NamesFixture: Decodable {
    struct Stream: Decodable {
        let seed: UInt32
        let names: [String]
    }
    let streams: [Stream]
}

struct SnapshotFixture: Decodable {
    struct Case: Decodable {
        let seed: UInt32
        let snapshot: ProjectSnapshotJSON
    }
    struct ProjectSnapshotJSON: Decodable {
        let bpm: Int
        let root_pc: Int
        let scale: String
        let tracks: [Track]
    }
    struct Track: Decodable {
        let voiceIdx: Int
        let muted: Bool
        let cells: [Double]
    }
    let cases: [Case]
}

// ------------------------------------------------------------- comparisons --

/// Largest relative difference across two sequences, which is the number
/// worth reporting when a tolerance is involved: it says how far apart the
/// platforms actually are, not just whether they passed.
func maxRelativeError(_ a: [Double], _ b: [Double]) -> Double {
    precondition(a.count == b.count, "length mismatch: \(a.count) vs \(b.count)")
    var worst = 0.0
    for (x, y) in zip(a, b) {
        if x == y { continue }
        let scale = Swift.max(abs(x), abs(y), .leastNormalMagnitude)
        worst = Swift.max(worst, abs(x - y) / scale)
    }
    return worst
}
