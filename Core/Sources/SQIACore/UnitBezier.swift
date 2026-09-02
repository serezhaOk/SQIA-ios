// A timing curve, worked out here rather than left to whoever is drawing.
//
// The mixer's move is drawn twice: by Metal, on the display link the field
// already runs on, and by SwiftUI, for the chips and the tile that fade with
// it. Those two have no animation they can share — one is a number advanced
// per frame, the other is a `withAnimation` the framework owns — so what they
// share instead is the curve. The four numbers are stated once, evaluated
// here for the field and handed to `Animation.timingCurve` for the rest.

import Foundation

/// The unit cubic Bézier that CSS writes as `cubic-bezier(x1, y1, x2, y2)`: a
/// curve from (0, 0) to (1, 1) with those two control points, read as how far
/// through the move against how far through the time.
///
/// Both control points are expected inside the unit square, which is what
/// keeps the curve a function of time — one answer per moment — and keeps the
/// answer between nought and one, with no overshoot to undo.
public struct UnitBezier: Sendable, Equatable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// How far through the move, a fraction `t` of the way through the time.
    public func value(at t: Double) -> Double {
        let time = min(max(t, 0), 1)
        // The ends are exact rather than solved for: a move that stops a
        // billionth short of its end is a move that never quite arrives.
        if time <= 0 { return 0 }
        if time >= 1 { return 1 }
        return y(at: parameter(for: time))
    }

    // ---------------------------------------------------------- the curve --

    // The polynomial form, which is what a solver wants:
    // x(u) = ((ax·u + bx)·u + cx)·u, and y the same with its own three.
    private var cx: Double { 3 * x1 }
    private var bx: Double { 3 * (x2 - x1) - cx }
    private var ax: Double { 1 - cx - bx }
    private var cy: Double { 3 * y1 }
    private var by: Double { 3 * (y2 - y1) - cy }
    private var ay: Double { 1 - cy - by }

    private func x(at u: Double) -> Double { ((ax * u + bx) * u + cx) * u }
    private func y(at u: Double) -> Double { ((ay * u + by) * u + cy) * u }
    private func gradient(at u: Double) -> Double { (3 * ax * u + 2 * bx) * u + cx }

    /// The curve is written in terms of its own parameter and asked about in
    /// terms of time, so the parameter has to be found before an answer can be
    /// read off it.
    ///
    /// Newton first: on a curve whose control points are inside the square it
    /// lands in three or four steps. Bisection after it, for the flat stretch
    /// of a curve where Newton has nowhere to step.
    private func parameter(for time: Double) -> Double {
        var u = time
        for _ in 0..<8 {
            let error = x(at: u) - time
            if abs(error) < 1e-9 { return u }
            let slope = gradient(at: u)
            if abs(slope) < 1e-9 { break }
            u -= error / slope
        }

        var low = 0.0
        var high = 1.0
        u = time
        while high - low > 1e-9 {
            let here = x(at: u)
            if abs(here - time) < 1e-9 { break }
            if here > time { high = u } else { low = u }
            u = (low + high) / 2
        }
        return u
    }
}
