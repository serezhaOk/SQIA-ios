// Every number the heat field is drawn by, in one place and on a slider.
//
// The synth tuning next door exists because a sound cannot be judged from
// its source; this exists for the same reason and is the same idea. None of
// these can be settled anywhere but on a screen — how far a note spreads,
// how long its colour takes to come back, where the ramp turns — and reading
// them off a diff is no way to decide any of it.
//
// It is a value rather than a pile of globals so it can ride on the layout
// the way the style does, and so what somebody arrives at by eye can be
// written down and read back.

import Foundation

/// One stop on a colour ramp: where it sits, and what colour it is there.
public struct ColorStop: Sendable, Equatable, Codable {
    /// 0…1 along the ramp.
    public var at: Double
    public var color: RGB

    public init(at: Double, _ color: RGB) {
        self.at = at
        self.color = color
    }
}

public struct FieldTuning: Sendable, Equatable, Codable {
    // ------------------------------------------------------------- shape --

    /// How large a mark is at the very rim, against the middle. Below one it
    /// tapers; at one the grid is flat and reads as a weight on the screen.
    public var rimScale: Double
    /// What the middle adds on top of that.
    public var centreLift: Double
    /// The resting grid's dots.
    public var dotScale: Double
    /// The blobs a drawn note makes.
    public var blobScale: Double

    // ------------------------------------------------------------ motion --

    /// How long a struck note takes to give its colour back, in seconds.
    public var returnSeconds: Double
    /// How much further a note reaches while it is hot.
    public var spread: Double
    /// The ring travelling out of a struck blob.
    public var rippleFrequency: Double
    public var rippleSpeed: Double
    public var rippleAmplitude: Double

    // ------------------------------------------------------------ colour --

    /// How far the sum is stretched across the ramp — where cool ends and
    /// hot begins.
    public var gain: Double
    /// Below this the field dissolves into the ground.
    public var edge: Double
    /// The resting grid.
    public var hint: RGB
    /// A note that is only drawn.
    public var rest: [ColorStop]
    /// A note that is sounding.
    public var heat: [ColorStop]

    public init(
        rimScale: Double,
        centreLift: Double,
        dotScale: Double,
        blobScale: Double,
        returnSeconds: Double,
        spread: Double,
        rippleFrequency: Double,
        rippleSpeed: Double,
        rippleAmplitude: Double,
        gain: Double,
        edge: Double,
        hint: RGB,
        rest: [ColorStop],
        heat: [ColorStop]
    ) {
        self.rimScale = rimScale
        self.centreLift = centreLift
        self.dotScale = dotScale
        self.blobScale = blobScale
        self.returnSeconds = returnSeconds
        self.spread = spread
        self.rippleFrequency = rippleFrequency
        self.rippleSpeed = rippleSpeed
        self.rippleAmplitude = rippleAmplitude
        self.gain = gain
        self.edge = edge
        self.hint = hint
        self.rest = rest
        self.heat = heat
    }

    /// How many stops each ramp carries. The panel and the shader both count
    /// on this, so it is stated once.
    public static let restStops = 5
    public static let heatStops = 8

    /// Where the field stands now. Everything here was arrived at by eye.
    public static let current = FieldTuning(
        rimScale: 0.72,
        centreLift: 0.62,
        dotScale: 0.62,
        blobScale: 1,
        returnSeconds: 1,
        spread: 0.55,
        rippleFrequency: 4.5,
        rippleSpeed: 1.6,
        rippleAmplitude: 0.16,
        gain: 0.26,
        edge: 0.12,
        hint: RGB(198, 158, 48),
        rest: [
            ColorStop(at: 0, RGB(77, 56, 13)),
            ColorStop(at: 0.30, RGB(168, 122, 18)),
            ColorStop(at: 0.55, RGB(230, 184, 31)),
            ColorStop(at: 0.78, RGB(252, 224, 77)),
            ColorStop(at: 1, RGB(255, 247, 189)),
        ],
        heat: [
            ColorStop(at: 0, RGB(92, 133, 219)),
            ColorStop(at: 0.22, RGB(51, 97, 212)),
            ColorStop(at: 0.42, RGB(107, 173, 230)),
            ColorStop(at: 0.55, RGB(219, 237, 242)),
            ColorStop(at: 0.66, RGB(252, 237, 158)),
            ColorStop(at: 0.78, RGB(252, 204, 51)),
            ColorStop(at: 0.89, RGB(245, 133, 31)),
            ColorStop(at: 1, RGB(222, 41, 26)),
        ]
    )

    public var isDefault: Bool { self == .current }

    /// The whole set as JSON, so a look arrived at by eye can be written back
    /// into the source rather than remembered.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    public static func decoded(from text: String) -> FieldTuning? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FieldTuning.self, from: data)
    }
}

extension RGB {
    /// `RRGGBB`, the form colours get typed in.
    public var hex: String {
        func byte(_ n: Double) -> Int { max(0, min(255, Int(n.rounded()))) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Reads `RRGGBB` or `#RRGGBB`, and nothing else — a half-typed value
    /// should leave the colour alone rather than jump somewhere on its way.
    public init?(hex text: String) {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF))
    }
}
