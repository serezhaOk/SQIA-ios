// The timing curve, against the definition it is named after.
//
// The solver is the part worth testing: the curve is written in terms of its
// own parameter and asked about in terms of time, and everything between the
// two ends depends on that inversion being right. So the test walks the curve
// forwards, by the Bernstein form written out here, and asks the solver to
// walk it back — a point that is on the curve at parameter `u` has to come
// back as the same point when it is asked for by its time.

import Foundation
import Testing

@testable import SQIACore

@Suite("Unit Bézier")
struct UnitBezierTests {
    /// The mixer's, which is the one that has to be right.
    private let curve = MixerLayout.curve

    /// The curve as CSS defines it, straight from the Bernstein form and with
    /// no solving anywhere in it.
    private func point(_ bezier: UnitBezier, at u: Double) -> (x: Double, y: Double) {
        let v = 1 - u
        return (
            x: 3 * v * v * u * bezier.x1 + 3 * v * u * u * bezier.x2 + u * u * u,
            y: 3 * v * v * u * bezier.y1 + 3 * v * u * u * bezier.y2 + u * u * u
        )
    }

    @Test("Both ends are exact")
    func ends() {
        #expect(curve.value(at: 0) == 0)
        #expect(curve.value(at: 1) == 1)
        // Asked outside its time, it answers with the end it is nearest —
        // a frame arriving a moment late must not run the move backwards.
        #expect(curve.value(at: -0.5) == 0)
        #expect(curve.value(at: 1.5) == 1)
    }

    @Test("Asked by time, it gives back the point the curve has at that time")
    func inverts() {
        for step in 0...200 {
            let u = Double(step) / 200
            let (x, y) = point(curve, at: u)
            #expect(abs(curve.value(at: x) - y) < 1e-6)
        }
    }

    @Test("The straight one is the one that changes nothing")
    func identity() {
        let straight = UnitBezier(1.0 / 3, 1.0 / 3, 2.0 / 3, 2.0 / 3)
        for step in 0...100 {
            let t = Double(step) / 100
            #expect(abs(straight.value(at: t) - t) < 1e-6)
        }
    }

    @Test("It never goes backwards, and never past either end")
    func monotonic() {
        var last = 0.0
        for step in 0...1000 {
            let here = curve.value(at: Double(step) / 1000)
            #expect(here >= last - 1e-12)
            #expect(here >= 0 && here <= 1)
            last = here
        }
    }
}
