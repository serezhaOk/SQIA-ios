// Where the tracks sit when the mixer is open, and how they get there.
//
// Port of the mixer geometry in the web app's src/main.ts. The numbers were
// measured off a 375x812 mockup: ten points of outer margin, a seventeen
// point gutter, and panels that keep a 1:1.6 shape and start a fixed
// fraction down the stage. The strip along the bottom is left for the
// "Back to projects" tile.
//
// None of it touches a view, so all of it can be checked against the web's
// own arithmetic.
//
// The timing is no longer the web's. Everything on this transition — the
// panels, the ground they lie on, the controls that come and go with them —
// is given the one duration and the one curve below, so that it reads as a
// single move rather than as several that happen to start together.

import Foundation

public struct Panel: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }
}

public enum MixerLayout {
    public static let margin = 10.0
    public static let gutter = 17.0
    /// The mockup's panel is 168.75 by 270.
    public static let panelRatio = 270.0 / 168.75
    /// Kept clear at the bottom for the tile that leaves the mixer.
    public static let buttonRoom = 100.0
    /// A panel is never allowed to collapse below this, however short the
    /// screen is.
    public static let minimumHeight = 80.0
    /// How far down the stage the panels start.
    public static let topFraction = 0.108

    /// The corner a panel is cut to. Both the hairline round it and the
    /// field inside it read this, and a border on one curve with a picture
    /// on another would look like a mistake, so it is one number.
    public static let corner = 26.0

    /// How long the view takes to travel between full screen and the mixer.
    ///
    /// One number for the whole move: the panels flying, the ground turning
    /// over under them, the chips and the tile fading in and out. Anything on
    /// this transition that took its own time would arrive on its own, and
    /// four things arriving one after another is four moves rather than one.
    public static let transition = 0.4

    /// And one curve, for the same reason. Written as CSS writes it —
    /// `cubic-bezier(0.79, 0.14, 0.15, 0.86)` — which holds nearly still for
    /// the first third, goes most of the way through the middle of the move,
    /// and eases out of the last of it.
    ///
    /// It is stated here rather than in the view because the field is not
    /// animated by SwiftUI: the travel is advanced per frame on the display
    /// link, and the only way the two halves of the screen can agree is by
    /// reading the same four numbers.
    public static let curve = UnitBezier(0.79, 0.14, 0.15, 0.86)

    /// The chip strip — name on the left, mute on the right — sits inside
    /// the panel over its last rows of dots, so the field keeps the whole
    /// panel to itself.
    public static let chipHeight = 30.0
    public static let chipInset = 8.0

    /// Where track `index` sits: one column per track, left to right.
    public static func panel(
        _ index: Int,
        of count: Int,
        width: Double,
        height: Double
    ) -> Panel {
        let tracks = max(1, count)
        let w = (width - margin * 2 - gutter * Double(tracks - 1)) / Double(tracks)
        let y = (height * topFraction).rounded()
        let h = max(minimumHeight, min(w * panelRatio, height - y - buttonRoom))
        return Panel(x: margin + Double(index) * (w + gutter), y: y, width: w, height: h)
    }

    public static func full(width: Double, height: Double) -> Panel {
        Panel(x: 0, y: 0, width: width, height: height)
    }

    /// The strip the name and mute chips live in.
    public static func chips(in panel: Panel) -> Panel {
        Panel(
            x: panel.x + chipInset,
            y: panel.maxY - chipInset - chipHeight,
            width: panel.width - chipInset * 2,
            height: chipHeight)
    }

    /// Which panel a touch landed in, or nil for the space between them.
    public static func hit(
        x: Double,
        y: Double,
        count: Int,
        width: Double,
        height: Double
    ) -> Int? {
        for index in 0..<max(1, count) {
            if panel(index, of: count, width: width, height: height).contains(x: x, y: y) {
                return index
            }
        }
        return nil
    }

    // ---------------------------------------------------------- the travel --

    /// Where the move has got to, a fraction `t` of the way through its time.
    ///
    /// Not the web's cubic ease any more: the web eased in and out evenly
    /// about the middle, and this one is weighted, so that the panels are
    /// most of the way home while there is still time left to settle into it.
    public static func ease(_ t: Double) -> Double {
        curve.value(at: t)
    }

    public static func lerp(_ a: Panel, _ b: Panel, _ t: Double) -> Panel {
        Panel(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t)
    }

    /// Move the animation on by one frame, at the rate `transition` sets.
    /// Linear: the curve is applied to the result by `ease`, not to the
    /// travel, so that the number itself stays something a frame can be
    /// counted against.
    public static func advance(_ value: Double, toward target: Double, dt: Double) -> Double {
        let speed = dt / transition
        return target > value
            ? min(target, value + speed)
            : max(target, value - speed)
    }

    // ------------------------------------------------------ what is drawn --

    /// The active track flies between full screen and its slot; the others
    /// wait in theirs.
    public static func rect(
        forTrack index: Int,
        active: Int,
        count: Int,
        width: Double,
        height: Double,
        eased t: Double
    ) -> Panel {
        let slot = panel(index, of: count, width: width, height: height)
        guard index == active else { return slot }
        return lerp(full(width: width, height: height), slot, t)
    }

    /// The corner the travelling panel is cut to, and filled on.
    ///
    /// Square while the track is the whole screen and the panel's own by the
    /// time it has become a card. A fixed radius would cut four notches out of
    /// the ground the moment the mixer began to open, and the screen would
    /// show the mixer's grey through the corners of a field that still fills
    /// it. The slots the other tracks wait in are cards the whole way, so
    /// theirs never changes.
    public static func travellingCorner(active: Bool, eased t: Double) -> Double {
        active ? corner * t : corner
    }

    /// The active track is always visible; the rest fade in with the mixer,
    /// and a muted track is dimmed wherever it is.
    public static func alpha(active: Bool, eased t: Double, muted: Bool) -> Double {
        let base = active ? 1 : t
        return muted ? base * 0.35 : base
    }

    /// A panel's own ground — the black a card is filled with.
    ///
    /// The track being looked at carries it the whole way, because that
    /// ground is the screen it is flying out of; the others arrive with the
    /// mixer, like their outlines. Muting does not come into it: a muted
    /// track's notes are dimmed, but the card they are drawn on is a card
    /// like any other.
    public static func fillAlpha(active: Bool, eased t: Double) -> Double {
        active ? 1 : t
    }

    /// The extras — halos and streaks — are scaled back in a panel, and the
    /// flying track loses half of its own on the way in.
    public static func detail(active: Bool, eased t: Double) -> Double {
        active ? 1 - t * 0.5 : 0.4
    }

    /// The slot outlines fade in with the mixer.
    public static func outlineAlpha(eased t: Double) -> Double {
        0.7 * t
    }
}
