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

    /// How long the view takes to travel between full screen and the mixer.
    public static let transition = 0.35

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

    /// The web's ease, which is the cubic one: slow away, quick through the
    /// middle, slow in.
    public static func ease(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    public static func lerp(_ a: Panel, _ b: Panel, _ t: Double) -> Panel {
        Panel(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t)
    }

    /// Move the animation on by one frame, at the web's rate.
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

    /// The active track is always visible; the rest fade in with the mixer,
    /// and a muted track is dimmed wherever it is.
    public static func alpha(active: Bool, eased t: Double, muted: Bool) -> Double {
        let base = active ? 1 : t
        return muted ? base * 0.35 : base
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
