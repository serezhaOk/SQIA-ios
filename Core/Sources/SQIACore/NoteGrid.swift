// The note matrix: 12 notes across, 16 steps down, each cell an intensity
// 0…1 (0 = empty, ~0.5 = soft bleed, 1 = bright accent).
//
// Port of the editing half of the web app's src/grid.ts. The rendering half
// — flash energy, colour ripples, the dome — is not state a pattern carries,
// so it lives with the renderer instead.
//
// Cells are `Float` and the arithmetic is `Double` because that is exactly
// what the web does: a Float32Array written from double-precision maths. Keep
// it that way or the fixtures drift.

public struct NoteGrid: Sendable, Equatable {
    public static let rows = 16
    public static let columns = Music.columns
    public static let count = rows * columns

    public private(set) var cells: [Float]

    public init() {
        cells = Array(repeating: 0, count: NoteGrid.count)
    }

    /// Rebuild from a stored pattern. Values outside the grid are dropped and
    /// a short array leaves the rest empty, matching how the web app applies
    /// a project row it does not fully recognise.
    public init(cells stored: [Double]) {
        self.init()
        for (i, v) in stored.enumerated() where i < NoteGrid.count && v > 0 {
            cells[i] = Float(v)
        }
    }

    public func at(row: Int, column: Int) -> Float {
        guard row >= 0, row < NoteGrid.rows, column >= 0, column < NoteGrid.columns else { return 0 }
        return cells[row * NoteGrid.columns + column]
    }

    private mutating func set(_ row: Int, _ column: Int, _ v: Float) {
        guard row >= 0, row < NoteGrid.rows, column >= 0, column < NoteGrid.columns else { return }
        cells[row * NoteGrid.columns + column] = v
    }

    /// Raise a cell to `v`, never lower it — bleeding into a cell that is
    /// already brighter leaves it alone.
    private mutating func bleed(_ row: Int, _ column: Int, _ v: Double) {
        guard row >= 0, row < NoteGrid.rows, column >= 0, column < NoteGrid.columns else { return }
        let i = row * NoteGrid.columns + column
        let value = Float(v)
        if cells[i] < value { cells[i] = value }
    }

    /// Organic brush driven by the finger's fractional position. The cell
    /// under the finger goes full; neighbours bleed in proportion to how
    /// close the finger is to that edge, so a drag leaves a soft directional
    /// trail.
    ///
    /// `gx`/`gy` are in cell units. Out-of-range (or NaN) does nothing.
    public mutating func brush(gx: Double, gy: Double) {
        guard gx >= 0, gx < Double(NoteGrid.columns), gy >= 0, gy < Double(NoteGrid.rows) else { return }
        let c = Int(gx.rounded(.down))
        let r = Int(gy.rounded(.down))

        let fx = gx - Double(c) - 0.5  // -0.5…0.5 from the cell centre
        let fy = gy - Double(r) - 0.5
        let sx = fx >= 0 ? 1 : -1
        let sy = fy >= 0 ? 1 : -1
        let wx = min(1, abs(fx) * 2)
        let wy = min(1, abs(fy) * 2)
        let b = 0.9

        bleed(r, c, 1)
        bleed(r, c + sx, wx * b)
        bleed(r + sy, c, wy * b)
        bleed(r + sy, c + sx, wx * wy * b)
    }

    /// Softer symmetric stamp, used by the randomiser.
    public mutating func stamp(row: Int, column: Int) {
        bleed(row, column, 1)
        bleed(row - 1, column, 0.45)
        bleed(row + 1, column, 0.45)
        bleed(row, column - 1, 0.45)
        bleed(row, column + 1, 0.45)
    }

    /// Clears a 2×2 block, anchored so it always stays on the grid.
    public mutating func erase(row: Int, column: Int) {
        let r0 = min(row, NoteGrid.rows - 2)
        let c0 = min(column, NoteGrid.columns - 2)
        set(r0, c0, 0)
        set(r0 + 1, c0, 0)
        set(r0, c0 + 1, 0)
        set(r0 + 1, c0 + 1, 0)
    }

    public mutating func clear() {
        for i in cells.indices { cells[i] = 0 }
    }

    /// True when the track holds any notes at all.
    public var hasNotes: Bool {
        cells.contains { $0 > 0 }
    }

    /// Scatter accents within the scale — the columns are already in key, so
    /// anything this draws is musical.
    public mutating func randomize(using random: RandomSource) {
        clear()
        for r in 0..<NoteGrid.rows where random.chance(0.42) {
            stamp(row: r, column: random.index(NoteGrid.columns))
            if random.chance(0.25) {
                stamp(row: r, column: random.index(NoteGrid.columns))
            }
        }
    }
}
