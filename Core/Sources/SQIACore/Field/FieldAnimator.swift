// The live field: what makes the dots feel like a surface rather than a
// grid.
//
// A note that sounds blooms, shoves its neighbours outward as though the
// field were jelly, throws a streak away from the centre and sends a colour
// ripple out ring by ring. Underneath it all the field breathes, so it is
// never quite still.
//
// Port of the drawing half of the web app's src/grid.ts. Nothing here draws:
// it produces the list of primitives to draw, which is what lets the whole
// thing be compared against the web primitive for primitive rather than
// screenshot against screenshot.

import Foundation

public struct RGB: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGB(255, 255, 255)

    /// Colour as a CSS string would carry it — the web builds `rgba(...)`
    /// from these, and `| 0` truncates.
    var truncated: RGB {
        RGB(red.rounded(.towardZero), green.rounded(.towardZero), blue.rounded(.towardZero))
    }

    /// The web caches one halo sprite per colour and quantises to keep that
    /// cache small. It is a rendering detail that shows: white becomes 256,
    /// which the canvas then clamps back to 255.
    var quantised: RGB {
        func q(_ n: Double) -> Double { (n / 32).rounded() * 32 }
        return RGB(q(red), q(green), q(blue))
    }
}

/// One primitive to draw, in the order the web draws them.
public struct FieldDraw: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case dot
        case glow
        case streak
        /// A contribution to a summed field rather than something drawn on
        /// its own. Sources near each other add up, and what gets drawn is
        /// the total — which is what makes two notes side by side one shape
        /// instead of two circles. Not the web's; no fixture produces one.
        case source
    }

    public var kind: Kind
    /// Dot and streak: the centre / the start. Glow: its top-left corner,
    /// which is how the web places its sprite.
    public var x: Double
    public var y: Double
    /// Streak only: where it ends.
    public var x1: Double = 0
    public var y1: Double = 0
    /// Dot: radius. Glow: width and height. Streak: line width. Source: the
    /// radius its falloff reaches.
    public var size: Double
    public var color: RGB
    /// Source: how much it contributes at its middle.
    public var alpha: Double
    /// Source only: how hot the flash under it still is, carried so the
    /// colour can ripple out of a blob that was struck without the ones
    /// beside it moving in step.
    public var energy: Double = 0
}

public final class FieldAnimator {
    // How hard a firing note pushes its neighbours out, how far that
    // reaches, and how fast the energy behind it falls away.
    public static let push = 0.62  // in cell units
    public static let pushRadius = 2.4  // in cell units
    public static let decay = 3.1  // energy falloff per second

    // The colour wave: a played note strobes yellow, green, violet in hard
    // steps and snaps back to white, and the flicker spreads ring by ring.
    public static let waveRadius = 4.0  // cells
    public static let waveRingDelay = 0.05  // seconds per ring
    public static let waveStep = 0.09  // seconds each colour is held
    public static let maxWaves = 48

    public static let waveStops: [RGB] = [
        RGB(255, 214, 0),  // yellow
        RGB(80, 255, 130),  // green
        RGB(176, 107, 255),  // violet
    ]

    /// The resting grid: the field's own green, dim enough to be a place
    /// to aim at rather than a mark.
    public static let hint = RGB(96, 206, 104)

    public static let waveDuration = Double(waveStops.count) * waveStep
    public static let waveLife = waveDuration + waveRadius * waveRingDelay

    private struct Wave {
        var row: Int
        var column: Int
        var t: Double
        var amp: Double
    }

    private struct Source {
        var row: Int
        var column: Int
        var energy: Double
    }

    /// Per-cell flash energy, 0…1, decaying after each hit. Float because
    /// that is what the web stores it in, and the rounding shows.
    public private(set) var energy = [Float](repeating: 0, count: NoteGrid.count)

    private var waves: [Wave] = []
    private var sources: [Source] = []
    private var time: Double = 0

    public init() {
        sources.reserveCapacity(NoteGrid.count)
    }

    public var activeWaveCount: Int { waves.count }

    /// A note just sounded — bloom it and send a colour ripple outward.
    public func flash(row: Int, column: Int, velocity: Double) {
        guard row >= 0, row < NoteGrid.rows, column >= 0, column < NoteGrid.columns else {
            return
        }
        let i = row * NoteGrid.columns + column
        let amp = 0.55 + 0.45 * velocity
        energy[i] = max(energy[i], Float(amp))
        if waves.count >= Self.maxWaves { waves.removeFirst() }
        waves.append(Wave(row: row, column: column, t: 0, amp: amp))
    }

    public func reset() {
        for i in energy.indices { energy[i] = 0 }
        waves.removeAll(keepingCapacity: true)
        sources.removeAll(keepingCapacity: true)
        time = 0
    }

    /// Move the field on by `dt` seconds: age the ripples, decay the blooms,
    /// and note which cells are still bending the field around them.
    public func advance(by dt: Double) {
        time += dt

        for i in waves.indices { waves[i].t += dt }
        if !waves.isEmpty { waves.removeAll { $0.t >= Self.waveLife } }

        let fade = exp(-Self.decay * dt)
        sources.removeAll(keepingCapacity: true)
        for row in 0..<NoteGrid.rows {
            for column in 0..<NoteGrid.columns {
                let i = row * NoteGrid.columns + column
                let e = Double(energy[i])
                if e <= 0.002 {
                    energy[i] = 0
                    continue
                }
                energy[i] = Float(e * fade)
                sources.append(
                    Source(row: row, column: column, energy: Double(energy[i])))
            }
        }
    }

    /// Hard-stepped colour at 0…1 through the cycle — no blending.
    static func waveColor(phase: Double) -> RGB {
        let index = min(
            waveStops.count - 1,
            max(0, Int((phase * Double(waveStops.count)).rounded(.down)))
        )
        return waveStops[index]
    }

    /// Colour tint for a cell: the strongest ripple currently passing
    /// through it, or nothing when the cell is plain white.
    private func tint(row: Int, column: Int) -> (rgb: RGB, amp: Double)? {
        var best: (rgb: RGB, amp: Double)?
        for wave in waves {
            let d = hypot(Double(row - wave.row), Double(column - wave.column))
            if d > Self.waveRadius { continue }
            let local = wave.t - d * Self.waveRingDelay
            if local <= 0 || local >= Self.waveDuration { continue }

            let phase = local / Self.waveDuration
            // Full strength while it passes — the flicker cuts, it does not
            // fade. Each colour also strobes within its own slot.
            let sub = local.truncatingRemainder(dividingBy: Self.waveStep) / Self.waveStep
            let strobe = sub < 0.62 ? 1.0 : 0.4
            let amp = wave.amp * (1 - (d / (Self.waveRadius + 1)) * 0.55) * strobe
            if best == nil || amp > best!.amp {
                best = (Self.waveColor(phase: phase), amp)
            }
        }
        return best
    }

    /// Everything to draw for one frame, in order.
    ///
    /// `detail` scales the expensive extras down for a thumbnail and
    /// `alpha` fades the whole field during a view transition.
    public func draws(
        grid: NoteGrid,
        layout: FieldLayout,
        playhead: Int,
        detail: Double = 1,
        alpha: Double = 1,
        into out: inout [FieldDraw]
    ) {
        out.removeAll(keepingCapacity: true)

        let cell = layout.cell
        let pushRadius = Self.pushRadius * cell
        let baseDot = max(1.6, cell * 0.075)
        let a = max(0, min(1, alpha))
        if a <= 0.01 { return }
        let heat = layout.style.heat

        for row in 0..<NoteGrid.rows {
            let onHead = row == playhead
            for column in 0..<NoteGrid.columns {
                let i = row * NoteGrid.columns + column
                let v = Double(grid.cells[i])
                let e = Double(energy[i])

                var px = layout.ox + (Double(column) + 0.5) * cell
                var py = layout.oy + (Double(row) + 0.5) * cell

                // Nearby blooms shove this dot outward — the lens feel. Each
                // source acts on the position the one before it left, so the
                // order of the sources is part of the result.
                var swell = 0.0
                for source in sources {
                    let sx = layout.ox + (Double(source.column) + 0.5) * cell
                    let sy = layout.oy + (Double(source.row) + 0.5) * cell
                    let dx = px - sx
                    let dy = py - sy
                    let d2 = dx * dx + dy * dy
                    if d2 > pushRadius * pushRadius { continue }
                    let d = d2.squareRoot()
                    let fall = exp(-(d2 / (pushRadius * pushRadius)) * 2.2)
                    swell += source.energy * fall
                    if d > 1e-3 {
                        let amp = source.energy * fall * Self.push * cell
                        px += (dx / d) * amp
                        py += (dy / d) * amp
                    }
                }

                let warped = Field.warp(x: px, y: py, in: layout)
                let lens = Field.warpScale(x: px, y: py, in: layout)

                // Ambient breathing, so the field is never quite still.
                let breathe =
                    0.86 + 0.14
                    * sin(time * 1.5 + (Double(row) * 0.9 + Double(column) * 0.6))

                let tinted = tint(row: row, column: column)
                let colour: RGB =
                    tinted.map { t in
                        RGB(
                            255 + (t.rgb.red - 255) * t.amp,
                            255 + (t.rgb.green - 255) * t.amp,
                            255 + (t.rgb.blue - 255) * t.amp
                        )
                    } ?? .white
                let inkColour = colour.truncated

                if heat {
                    // Only a drawn note is a source. An empty cell would
                    // otherwise leave the screen blank, and a blank screen
                    // is one you cannot aim at — so it gets a dot far too
                    // faint to read as a mark, outside the field entirely.
                    if v <= 0 {
                        out.append(
                            FieldDraw(
                                kind: .dot, x: warped.x, y: warped.y,
                                size: baseDot * 0.62 * breathe,
                                color: Self.hint, alpha: 0.16 * breathe * a))
                        continue
                    }

                    // Weight is what the sum is made of, so this is where a
                    // cluster earns its heat: a lone note stays cool because
                    // nothing adds to it, and neighbours pile up into a core.
                    // A struck note leans on the sum for as long as the
                    // flash lasts.
                    let weight = v * (1 + 0.9 * e)
                    // Generous on purpose. The brush bleeds into the cells
                    // around the one under the finger, so a stroke lays down
                    // a run of sources whose falloffs have to overlap enough
                    // to close up into one shape.
                    let reach = cell * (0.95 + 0.5 * v) * (0.97 + 0.03 * breathe)
                    out.append(
                        FieldDraw(
                            kind: .source, x: warped.x, y: warped.y,
                            size: reach, color: Self.hint, alpha: weight * a,
                            energy: min(1, e)))
                    continue
                }

                if v <= 0 && e <= 0 {
                    let lift = tinted.map { $0.amp * 0.85 } ?? 0
                    let radius = baseDot * lens * breathe * (1 + lift * 0.6)
                    let dotAlpha = ((onHead ? 0.5 : 0.2) + lift * 0.62) * breathe
                    out.append(
                        FieldDraw(
                            kind: .dot, x: warped.x, y: warped.y, size: radius,
                            color: inkColour, alpha: min(1, dotAlpha) * a))

                    if let tinted, tinted.amp > 0.12, detail > 0.5 {
                        let size = radius * 5
                        out.append(
                            FieldDraw(
                                kind: .glow,
                                x: warped.x - size / 2,
                                y: warped.y - size / 2,
                                size: size,
                                color: tinted.rgb.quantised,
                                alpha: min(0.45, tinted.amp * 0.5) * a))
                    }
                    continue
                }

                // Active dot: size and brightness from intensity plus the
                // energy still left in the flash.
                let pulse = 1 + 0.75 * e
                let radius =
                    (baseDot + v * cell * 0.2) * lens * pulse * (0.97 + 0.03 * breathe)
                let dotAlpha = min(1, 0.4 + 0.45 * v + 0.3 * e)

                // The halo stays tight, so a cluster of hits never washes
                // the screen out.
                let glowSize = radius * (3 + 2.6 * e)
                let glowAlpha =
                    min(
                        0.6,
                        0.12 * v + 0.34 * e + 0.05 * swell + (tinted?.amp ?? 0) * 0.2
                    ) * a
                out.append(
                    FieldDraw(
                        kind: .glow,
                        x: warped.x - glowSize / 2,
                        y: warped.y - glowSize / 2,
                        size: glowSize,
                        color: (tinted?.rgb ?? .white).quantised,
                        alpha: glowAlpha))

                // A radial streak away from the centre while the note is hot.
                if e > 0.05 && detail > 0.5 {
                    let dx = warped.x - layout.cx
                    let dy = warped.y - layout.cy
                    let distance = hypot(dx, dy)
                    let d = distance == 0 ? 1 : distance
                    let length = e * cell * (0.4 + 1.2 * (d / layout.radius))
                    out.append(
                        FieldDraw(
                            kind: .streak,
                            x: warped.x,
                            y: warped.y,
                            x1: warped.x + (dx / d) * length,
                            y1: warped.y + (dy / d) * length,
                            size: radius * 1.1,
                            color: inkColour,
                            alpha: 0.34 * e * a))
                }

                out.append(
                    FieldDraw(
                        kind: .dot, x: warped.x, y: warped.y, size: radius,
                        color: inkColour, alpha: dotAlpha * a))
            }
        }
    }

    public func draws(
        grid: NoteGrid,
        layout: FieldLayout,
        playhead: Int,
        detail: Double = 1,
        alpha: Double = 1
    ) -> [FieldDraw] {
        var out: [FieldDraw] = []
        draws(
            grid: grid, layout: layout, playhead: playhead, detail: detail, alpha: alpha,
            into: &out)
        return out
    }
}
