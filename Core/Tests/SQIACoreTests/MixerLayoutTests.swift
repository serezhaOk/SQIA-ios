// The mixer's geometry, against the web's own arithmetic.
//
// There is no fixture for this: the web computes it inline in a rAF loop
// with no seam to sample. What can be done instead is to work the same
// numbers out by hand from the mockup the web measured off — 375 by 812 —
// and check the port lands on them.

import Foundation
import Testing

@testable import SQIACore

@Suite("Mixer layout")
struct MixerLayoutTests {
    /// The mockup the web's constants were measured from.
    private let width = 375.0
    private let height = 812.0
    private let tracks = 2

    @Test("Panels sit where the mockup puts them")
    func panelsMatchTheMockup() {
        // (375 − 20 − 17) / 2 = 169, which is the mockup's 168.75 rounded up
        // by the arithmetic rather than by anyone's hand.
        let expectedWidth = (375.0 - 20 - 17) / 2
        let expectedY = (812.0 * 0.108).rounded()  // 88
        let expectedHeight = min(expectedWidth * (270 / 168.75), 812 - expectedY - 100)

        let left = MixerLayout.panel(0, of: tracks, width: width, height: height)
        let right = MixerLayout.panel(1, of: tracks, width: width, height: height)

        #expect(left.x == 10)
        #expect(abs(left.width - expectedWidth) < 1e-12)
        #expect(left.y == expectedY)
        #expect(abs(left.height - expectedHeight) < 1e-12)

        // One gutter apart, and the far edge is a margin from the screen.
        #expect(abs(right.x - (left.maxX + 17)) < 1e-12)
        #expect(abs(right.maxX - (width - 10)) < 1e-9)
        #expect(right.y == left.y)
        #expect(right.height == left.height)
    }

    @Test("Panels keep the mockup's shape until the screen is too short")
    func shapeGivesWayToFit() {
        let tall = MixerLayout.panel(0, of: tracks, width: width, height: height)
        #expect(abs(tall.height / tall.width - 270 / 168.75) < 1e-12)

        // On a short screen the tile at the bottom still gets its room, and
        // the panel gives up its proportions rather than its place.
        let short = MixerLayout.panel(0, of: tracks, width: width, height: 400)
        #expect(short.height < short.width * (270 / 168.75))
        #expect(short.maxY <= 400 - MixerLayout.buttonRoom + 1e-9)

        // And never collapses entirely.
        let tiny = MixerLayout.panel(0, of: tracks, width: width, height: 120)
        #expect(tiny.height >= MixerLayout.minimumHeight)
    }

    @Test("A touch lands in the panel it is over, and nowhere between them")
    func hitTesting() {
        let left = MixerLayout.panel(0, of: tracks, width: width, height: height)
        let right = MixerLayout.panel(1, of: tracks, width: width, height: height)

        func hit(_ x: Double, _ y: Double) -> Int? {
            MixerLayout.hit(x: x, y: y, count: tracks, width: width, height: height)
        }

        #expect(hit(left.x + 4, left.y + 4) == 0)
        #expect(hit(right.maxX - 4, right.maxY - 4) == 1)
        // The gutter belongs to neither, and so does everything above and
        // below the row.
        #expect(hit((left.maxX + right.x) / 2, left.y + 20) == nil)
        #expect(hit(left.x + 4, left.y - 4) == nil)
        #expect(hit(left.x + 4, left.maxY + 4) == nil)
    }

    @Test("The chips sit inside the panel, along its bottom")
    func chipsAreInside() {
        let panel = MixerLayout.panel(0, of: tracks, width: width, height: height)
        let strip = MixerLayout.chips(in: panel)

        #expect(strip.x == panel.x + 8)
        #expect(strip.maxX == panel.maxX - 8)
        #expect(strip.height == 30)
        #expect(strip.maxY == panel.maxY - 8)
        #expect(strip.y > panel.y)
    }

    // ------------------------------------------------------------ travel --

    @Test("The ease is the web's cubic, both halves of it")
    func easing() {
        #expect(MixerLayout.ease(0) == 0)
        #expect(MixerLayout.ease(1) == 1)
        #expect(abs(MixerLayout.ease(0.5) - 0.5) < 1e-12)
        // Slow away from either end, quick through the middle.
        #expect(MixerLayout.ease(0.25) < 0.25)
        #expect(MixerLayout.ease(0.75) > 0.75)
        // Symmetric about the middle, which is what makes opening and
        // closing feel like the same move.
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(abs(MixerLayout.ease(t) + MixerLayout.ease(1 - t) - 1) < 1e-12)
        }
    }

    @Test("The travel takes the third of a second the web gives it")
    func travelTakesItsTime() {
        let dt = 1.0 / 120
        var value = 0.0
        var frames = 0
        while value < 1 && frames < 1000 {
            value = MixerLayout.advance(value, toward: 1, dt: dt)
            frames += 1
        }
        #expect(value == 1)
        #expect(abs(Double(frames) * dt - MixerLayout.transition) < dt)

        // And back again at the same rate, without overshooting.
        frames = 0
        while value > 0 && frames < 1000 {
            value = MixerLayout.advance(value, toward: 0, dt: dt)
            frames += 1
        }
        #expect(value == 0)
        #expect(abs(Double(frames) * dt - MixerLayout.transition) < dt)
    }

    @Test("The active track flies to its slot and the others wait in theirs")
    func whatMoves() {
        let full = MixerLayout.full(width: width, height: height)
        let slot = MixerLayout.panel(0, of: tracks, width: width, height: height)

        // Compared with a tolerance rather than for equality: `a + (b − a)·1`
        // is not bit-for-bit `b`, in the web's arithmetic as much as in
        // this one, and the lerp is the web's.
        func near(_ a: Panel, _ b: Panel) -> Bool {
            abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
                && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
        }

        let start = MixerLayout.rect(
            forTrack: 0, active: 0, count: tracks, width: width, height: height, eased: 0)
        let end = MixerLayout.rect(
            forTrack: 0, active: 0, count: tracks, width: width, height: height, eased: 1)
        #expect(near(start, full))
        #expect(near(end, slot))

        // Halfway is halfway, and the other track has not moved at all.
        let middle = MixerLayout.rect(
            forTrack: 0, active: 0, count: tracks, width: width, height: height, eased: 0.5)
        #expect(abs(middle.width - (full.width + slot.width) / 2) < 1e-12)

        for t in [0.0, 0.5, 1.0] {
            let other = MixerLayout.rect(
                forTrack: 1, active: 0, count: tracks, width: width, height: height,
                eased: t)
            #expect(other == MixerLayout.panel(1, of: tracks, width: width, height: height))
        }
    }

    @Test("What fades, and what is dimmed")
    func alphaAndDetail() {
        // The track being looked at never fades; the others arrive with the
        // mixer.
        #expect(MixerLayout.alpha(active: true, eased: 0, muted: false) == 1)
        #expect(MixerLayout.alpha(active: false, eased: 0, muted: false) == 0)
        #expect(MixerLayout.alpha(active: false, eased: 1, muted: false) == 1)

        // A muted track is dimmed wherever it is.
        #expect(MixerLayout.alpha(active: true, eased: 1, muted: true) == 0.35)
        #expect(
            abs(MixerLayout.alpha(active: false, eased: 0.5, muted: true) - 0.5 * 0.35)
                < 1e-12)

        // The extras are scaled back in a panel; the flying track gives up
        // half of its own on the way in.
        #expect(MixerLayout.detail(active: true, eased: 0) == 1)
        #expect(MixerLayout.detail(active: true, eased: 1) == 0.5)
        #expect(MixerLayout.detail(active: false, eased: 1) == 0.4)

        // Outlines come in with the mixer and are never fully opaque.
        #expect(MixerLayout.outlineAlpha(eased: 0) == 0)
        #expect(MixerLayout.outlineAlpha(eased: 1) == 0.7)
    }

    @Test("A panel's ground travels with it, and squares off as it grows")
    func theGround() {
        // The track being looked at is standing on its ground the whole way:
        // it is the screen it flew out of, and the screen it becomes again.
        #expect(MixerLayout.fillAlpha(active: true, eased: 0) == 1)
        #expect(MixerLayout.fillAlpha(active: true, eased: 1) == 1)
        // The other cards arrive with the mixer, like their outlines.
        #expect(MixerLayout.fillAlpha(active: false, eased: 0) == 0)
        #expect(MixerLayout.fillAlpha(active: false, eased: 1) == 1)
        #expect(abs(MixerLayout.fillAlpha(active: false, eased: 0.5) - 0.5) < 1e-12)

        // Square while the track is the screen, a card's corner by the time
        // it is a card. Anything else would cut four notches of the mixer's
        // ground out of a field that still fills the screen.
        #expect(MixerLayout.travellingCorner(active: true, eased: 0) == 0)
        #expect(MixerLayout.travellingCorner(active: true, eased: 1) == MixerLayout.corner)
        #expect(
            abs(
                MixerLayout.travellingCorner(active: true, eased: 0.5)
                    - MixerLayout.corner / 2) < 1e-12)

        // A slot is a card the whole way through, so its corner never moves.
        for t in [0.0, 0.5, 1.0] {
            #expect(MixerLayout.travellingCorner(active: false, eased: t) == MixerLayout.corner)
        }
    }
}
