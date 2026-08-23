// The dome the dot field sits on.
//
// The field bulges toward the viewer: dots spread out and grow near the
// centre and pack tighter toward the rim, while the edges stay put. Drawing
// needs the forward map, and hit-testing a finger needs the inverse — which
// has no closed form, so it is solved numerically.
//
// Port of the geometry in the web app's src/grid.ts. Pure functions here;
// the renderer owns the caching.
//
// The dome is a choice rather than a fact, so it is carried in a `FieldStyle`
// on the layout instead of being wired into the arithmetic. Everything that
// already had a layout in hand therefore keeps working unchanged, and the
// parity suite still measures the web's geometry because that is what
// `.classic` is.

import Foundation

/// How a field is drawn — the part of its look that changes where things go
/// rather than what colour they are.
public struct FieldStyle: Sendable, Equatable {
    /// Dome strength. Zero lies flat.
    public var lensK: Double
    /// Whether dots swell toward the centre of the dome.
    public var swell: Bool
    /// Whether a sounding cell is drawn as an illustration rather than as a
    /// dot with its halo and streak.
    public var sprites: Bool

    public init(lensK: Double, swell: Bool, sprites: Bool) {
        self.lensK = lensK
        self.swell = swell
        self.sprites = sprites
    }

    /// The web's field, which the fixtures are generated from. The dome
    /// strength is the web's `LENS_K`.
    public static let classic = FieldStyle(lensK: 0.19, swell: true, sprites: false)

    /// Flat, with a flower on every note.
    public static let flat = FieldStyle(lensK: 0, swell: false, sprites: true)
}

/// Where the field sits inside a box, in points.
public struct FieldLayout: Sendable, Equatable {
    /// Side of one grid cell before warping.
    public let cell: Double
    /// Top-left of the unwarped grid.
    public let ox: Double
    public let oy: Double
    /// Centre of the box — the top of the dome.
    public let cx: Double
    public let cy: Double
    /// Half-diagonal of the grid; the dome's reference radius.
    public let radius: Double
    /// How this field is drawn. Defaulted, so every existing caller — and
    /// every fixture — goes on measuring the web's field.
    public let style: FieldStyle

    public init(
        cell: Double,
        ox: Double,
        oy: Double,
        cx: Double,
        cy: Double,
        radius: Double,
        style: FieldStyle = .classic
    ) {
        self.cell = cell
        self.ox = ox
        self.oy = oy
        self.cx = cx
        self.cy = cy
        self.radius = radius
        self.style = style
    }
}

public enum Field {
    // ------------------------------------------------------------ forward --

    /// Grid-space point → screen point, over the dome.
    public static func warp(x: Double, y: Double, in l: FieldLayout) -> (x: Double, y: Double) {
        let k = l.style.lensK
        if k == 0 { return (x, y) }
        let ux = (x - l.cx) / l.radius
        let uy = (y - l.cy) / l.radius
        let f = 1 + k * (1 - (ux * ux + uy * uy))
        return (l.cx + ux * l.radius * f, l.cy + uy * l.radius * f)
    }

    /// Local scale of the dome at a point — dots swell toward the centre.
    public static func warpScale(x: Double, y: Double, in l: FieldLayout) -> Double {
        guard l.style.swell else { return 1 }
        let ux = (x - l.cx) / l.radius
        let uy = (y - l.cy) / l.radius
        return 0.72 + 0.62 * max(0, 1 - (ux * ux + uy * uy))
    }

    // ------------------------------------------------------------ inverse --

    /// Screen point → grid-space point.
    ///
    /// The forward map takes a radius `t` to `t·(1 + K·(1 − t²))`; going back
    /// means solving that cubic for `t`, which Newton does in a handful of
    /// steps from a good starting guess (the radius itself).
    public static func unwarp(x: Double, y: Double, in l: FieldLayout) -> (x: Double, y: Double) {
        // Flat, and the inverse of doing nothing is doing nothing. Worth
        // saying out loud: drawing goes one way through `warp` and a finger
        // comes back the other, so the two have to agree about the dome or
        // painting lands in the wrong cell.
        let lensK = l.style.lensK
        if lensK == 0 { return (x, y) }

        let vx = (x - l.cx) / l.radius
        let vy = (y - l.cy) / l.radius
        let v = hypot(vx, vy)
        if v < 1e-6 { return (l.cx, l.cy) }

        var t = v
        for _ in 0..<6 {
            let f = t * (1 + lensK) - lensK * t * t * t - v
            let d = 1 + lensK - 3 * lensK * t * t
            t -= f / (abs(d) < 1e-4 ? 1e-4 : d)
        }
        let k = t / v
        return (l.cx + vx * l.radius * k, l.cy + vy * l.radius * k)
    }

    // ------------------------------------------------------------- layout --

    /// Cell size that keeps the warped grid inside a `width` × `height` box.
    ///
    /// The dome pushes dots outward, so the flat cell size would overflow.
    /// Measure the widest warped extent over the perimeter cells, shrink by
    /// what overflowed, and repeat — three passes is plenty to converge.
    public static func fitCell(
        width: Double,
        height: Double,
        style: FieldStyle = .classic
    ) -> Double {
        var cell = min(width / Double(NoteGrid.columns), height / Double(NoteGrid.rows))
        // Nothing is pushed outward on a flat field, so the flat cell size
        // already fits and the passes below would only shave it for nothing.
        if style.lensK == 0 { return cell }

        for _ in 0..<3 {
            let gw = cell * Double(NoteGrid.columns)
            let gh = cell * Double(NoteGrid.rows)
            // Box-local: the caller's offset cancels out of the measurement.
            let l = FieldLayout(
                cell: cell,
                ox: (width - gw) / 2,
                oy: (height - gh) / 2,
                cx: width / 2,
                cy: height / 2,
                radius: hypot(gw, gh) / 2,
                style: style
            )

            var maxX = 0.0
            var maxY = 0.0
            func probe(_ r: Int, _ c: Int) {
                let p = warp(
                    x: l.ox + (Double(c) + 0.5) * cell,
                    y: l.oy + (Double(r) + 0.5) * cell,
                    in: l
                )
                maxX = max(maxX, abs(p.x - width / 2))
                maxY = max(maxY, abs(p.y - height / 2))
            }
            for r in 0..<NoteGrid.rows {
                probe(r, 0)
                probe(r, NoteGrid.columns - 1)
            }
            for c in 0..<NoteGrid.columns {
                probe(0, c)
                probe(NoteGrid.rows - 1, c)
            }

            let pad = cell * 0.3  // room for the dot and its halo
            let s = min(
                (width / 2 - pad) / max(maxX, 1e-3),
                (height / 2 - pad) / max(maxY, 1e-3),
                1
            )
            if s > 0.995 { break }
            cell *= s
        }
        return cell
    }

    /// The layout for a box on screen: fitted cell, centred, dome on top.
    public static func layout(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        style: FieldStyle = .classic
    ) -> FieldLayout {
        let cell = fitCell(width: width, height: height, style: style)
        let gw = cell * Double(NoteGrid.columns)
        let gh = cell * Double(NoteGrid.rows)
        return FieldLayout(
            cell: cell,
            ox: x + (width - gw) / 2,
            oy: y + (height - gh) / 2,
            cx: x + width / 2,
            cy: y + height / 2,
            radius: hypot(gw, gh) / 2,
            style: style
        )
    }

    // -------------------------------------------------------- hit testing --

    /// Fractional grid coordinates under a point on screen, or nil if the
    /// point misses the field.
    public static func position(
        x: Double,
        y: Double,
        in l: FieldLayout
    ) -> (gx: Double, gy: Double)? {
        guard l.cell > 0 else { return nil }
        let w = unwarp(x: x, y: y, in: l)
        let gx = (w.x - l.ox) / l.cell
        let gy = (w.y - l.oy) / l.cell
        guard gx >= 0, gx < Double(NoteGrid.columns), gy >= 0, gy < Double(NoteGrid.rows) else {
            return nil
        }
        return (gx, gy)
    }

    /// The whole cell under a point — what the eraser works on.
    public static func hit(x: Double, y: Double, in l: FieldLayout) -> (row: Int, column: Int)? {
        guard let p = position(x: x, y: y, in: l) else { return nil }
        return (Int(p.gy.rounded(.down)), Int(p.gx.rounded(.down)))
    }
}
