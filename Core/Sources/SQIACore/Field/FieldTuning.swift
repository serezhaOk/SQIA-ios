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
    /// How much of that taper the blobs take, 0…1.
    ///
    /// Zero, and they are all the size the middle would make them. The
    /// taper is right for the resting grid — a grid of dots one size reads
    /// as a weight sitting on the screen — but it is wrong for the blobs:
    /// whether two of them close up is their reach against the gap between
    /// them, and the gap does not taper. Let them follow it and notes merge
    /// in the middle of the field and stay separate at the top and bottom,
    /// which reads as a distortion rather than as a surface.
    public var sourceTaper: Double
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
    /// The level the sum has to reach for the field to be there at all —
    /// the outline is the contour drawn where it crosses this.
    public var edge: Double
    /// How wide that contour is, in pixels. A number in pixels rather than
    /// in field values is the whole point: it is the same edge on a lone
    /// quiet note as on a burning cluster, which is not true of anything
    /// measured in the sum itself.
    public var softness: Double
    /// The resting grid.
    public var hint: RGB
    /// A note that is only drawn.
    public var rest: [ColorStop]
    /// A note that is sounding.
    public var heat: [ColorStop]

    public init(
        rimScale: Double,
        centreLift: Double,
        sourceTaper: Double,
        dotScale: Double,
        blobScale: Double,
        returnSeconds: Double,
        spread: Double,
        rippleFrequency: Double,
        rippleSpeed: Double,
        rippleAmplitude: Double,
        gain: Double,
        edge: Double,
        softness: Double,
        hint: RGB,
        rest: [ColorStop],
        heat: [ColorStop]
    ) {
        self.rimScale = rimScale
        self.centreLift = centreLift
        self.sourceTaper = sourceTaper
        self.dotScale = dotScale
        self.blobScale = blobScale
        self.returnSeconds = returnSeconds
        self.spread = spread
        self.rippleFrequency = rippleFrequency
        self.rippleSpeed = rippleSpeed
        self.rippleAmplitude = rippleAmplitude
        self.gain = gain
        self.edge = edge
        self.softness = softness
        self.hint = hint
        self.rest = rest
        self.heat = heat
    }

    /// How many stops each ramp carries. The panel and the shader both count
    /// on this, so it is stated once.
    public static let restStops = 5
    public static let heatStops = 8

    /// Where the field stands now.
    ///
    /// Arrived at on a screen and copied back out of the panel, which is the
    /// only way any of it could have been decided. Worth knowing rather than
    /// reading off:
    ///
    /// A drawn note is white at every stop but one — at 0.78 it takes the
    /// same pink the hot end of the heat ramp ends on, so a mid-loud note
    /// sitting at rest still carries a trace of the colour it would burn if
    /// it were struck. Every other stop stays white, and blank still means
    /// nothing is there.
    ///
    /// The taper is gentler than it was: four and a half tenths at the rim
    /// against a bit over a tenth added in the middle. The blobs do not take
    /// it either way — `sourceTaper` is zero, so they are all drawn at the
    /// size the middle would give them and notes close up the same wherever
    /// they are on the field.
    ///
    /// One number here is not the one that came out of the panel. `edge` was
    /// 0.42 when it meant the top of a fade running up from nothing; it now
    /// names the contour itself, and 0.21 is where that fade was half way —
    /// so the shapes keep the size they read at, with an edge instead of a
    /// gradient.
    public static let current = FieldTuning(
        rimScale: 0.4503124177455902,
        centreLift: 0.7611599922180176,
        sourceTaper: 0,
        dotScale: 0.7437907487154006,
        blobScale: 0.3790015555918217,
        returnSeconds: 1.1537100106477738,
        spread: 0.9145621061325073,
        rippleFrequency: 4.092169761657715,
        rippleSpeed: 6.574946403503418,
        rippleAmplitude: 0.22103413939476013,
        gain: 0.574427540898323,
        edge: 0.21,
        softness: 0.9,
        hint: RGB(255, 255, 255),
        rest: [
            ColorStop(at: 0, RGB(255, 255, 255)),
            ColorStop(at: 0.30, RGB(255, 255, 255)),
            ColorStop(at: 0.55, RGB(255, 255, 255)),
            ColorStop(at: 0.7799999713897705, RGB(255, 112, 226)),
            ColorStop(at: 1, RGB(255, 255, 255)),
        ],
        heat: [
            ColorStop(at: 0, RGB(92, 133, 219)),
            ColorStop(at: 0.22, RGB(51, 97, 212)),
            ColorStop(at: 0.42, RGB(107, 173, 230)),
            ColorStop(at: 0.55, RGB(219, 237, 242)),
            ColorStop(at: 0.6914083361625671, RGB(252, 237, 158)),
            ColorStop(at: 0.8195136189460754, RGB(252, 204, 51)),
            ColorStop(at: 0.8859473466873169, RGB(245, 133, 31)),
            ColorStop(at: 1, RGB(255, 112, 226)),
        ]
    )

    /// The web's own taper, and the amber the heat field shipped with before
    /// the panel existed.
    ///
    /// `.classic` is pinned to this rather than to `.current`, and that is
    /// the whole reason it exists: the geometry fixtures measure `warpScale`
    /// against numbers generated from the web, so leaving the classic style
    /// on whatever the panel last wrote would turn every evening of tuning
    /// into a red parity suite. The two are separate questions and they now
    /// have separate answers.
    public static let web = FieldTuning(
        rimScale: 0.72,
        centreLift: 0.62,
        sourceTaper: 1,
        dotScale: 0.62,
        blobScale: 1,
        returnSeconds: 1,
        spread: 0.55,
        rippleFrequency: 4.5,
        rippleSpeed: 1.6,
        rippleAmplitude: 0.16,
        gain: 0.26,
        edge: 0.12,
        softness: 0.9,
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

    private enum CodingKeys: String, CodingKey {
        case rimScale, centreLift, sourceTaper, dotScale, blobScale
        case returnSeconds, spread, rippleFrequency, rippleSpeed, rippleAmplitude
        case gain, edge, softness, hint, rest, heat
    }

    /// A missing key is not an error, and that is deliberate.
    ///
    /// A tuning is written down by copying JSON out of the panel and pasting
    /// it into this file, so a set written last week has to go on reading
    /// after a number is added this week — and Swift's synthesised decoder
    /// does not fall back on a property's default value, it throws, which
    /// would silently drop the whole set. Every field falls back on the
    /// build's own, so an older tuning loads and only the new number comes
    /// from here.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let built = FieldTuning.current
        func number(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            try box.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        rimScale = try number(.rimScale, built.rimScale)
        centreLift = try number(.centreLift, built.centreLift)
        sourceTaper = try number(.sourceTaper, built.sourceTaper)
        dotScale = try number(.dotScale, built.dotScale)
        blobScale = try number(.blobScale, built.blobScale)
        returnSeconds = try number(.returnSeconds, built.returnSeconds)
        spread = try number(.spread, built.spread)
        rippleFrequency = try number(.rippleFrequency, built.rippleFrequency)
        rippleSpeed = try number(.rippleSpeed, built.rippleSpeed)
        rippleAmplitude = try number(.rippleAmplitude, built.rippleAmplitude)
        gain = try number(.gain, built.gain)
        edge = try number(.edge, built.edge)
        softness = try number(.softness, built.softness)
        hint = try box.decodeIfPresent(RGB.self, forKey: .hint) ?? built.hint
        rest = try box.decodeIfPresent([ColorStop].self, forKey: .rest) ?? built.rest
        heat = try box.decodeIfPresent([ColorStop].self, forKey: .heat) ?? built.heat
    }

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
