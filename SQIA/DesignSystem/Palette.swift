// The palette, straight from the web app's style.css.
//
// SQIA is a black app with one near-white ink and a handful of greys, and
// no system colour anywhere — so these are plain sRGB values rather than
// semantic ones that would shift under us. The sequencer is the exception,
// and even there the ground is chosen by a switch in the debug panel rather
// than by the phone: `SequencerPalette`, below.

import Metal
import SwiftUI

enum Palette {
    /// `--bg`
    static let background = Color.black
    /// `--ui` — every UI element except the sequencer field.
    static let ui = Color(hex: 0xF5F3F3)
    /// `--card`
    static let card = Color(hex: 0x383838)
    /// `--ink` — the sequencer's own labels.
    static let ink = Color(hex: 0xD4CCCC)
    /// `--accent`
    static let accent = Color.white

    // Sign-in. Everything on that screen sits over a film rather than over
    // the black, so its ink is plain white at the weights the design gives
    // it and not one of the greys above.
    static let loginTagline = Color.white.opacity(0.7)
    static let loginTerms = Color.white.opacity(0.6)
    static let success = Color(hex: 0x9AD3A6)
    static let failure = Color(hex: 0xE08A80)

    // Projects and menus
    static let cardPressed = Color(hex: 0x444444)
    static let lightPressed = Color(hex: 0xE2DEDE)
    static let menu = Color(hex: 0x1E1E1E)
    static let menuBorder = Color(hex: 0x333333)
    static let menuPressed = Color(hex: 0x2C2C2C)
    static let danger = Color(hex: 0xFF6B6B)
    static let icon = Color(hex: 0xE3E3E3)

    // Sheet
    static let sheet = Color(hex: 0x1A1A1A)
    static let sheetGrip = Color(hex: 0x4A4A4A)
    static let scrim = Color.black.opacity(0.55)

    // The mark
    static let logoStroke = Color(hex: 0x4A4A4A)
}

/// The sequencer screen, from the Figma. Black, like the rest of the app — a
/// surface a shade off it for anything raised, and two weights of hairline.
/// The inset glow along the bottom of every raised control is what makes them
/// read as pressed out of the ground rather than laid on it.
///
/// A value rather than a shelf of constants, because the screen can be turned
/// over onto a light ground and every colour on it has to turn with it: a
/// white label left behind on a pale surface is not a dimmer version of the
/// design, it is an unreadable one. The chosen palette travels down the
/// screen in the environment, so no control has to be told which ground it is
/// standing on.
struct SequencerPalette: Equatable {
    /// The ground, as one number. SwiftUI paints the bars with it and Metal
    /// clears the field to it, and the screen only reads as a single surface
    /// for as long as those two agree — so they are given the same value
    /// rather than two that were chosen to match.
    var ground: UInt32
    /// Raised: pills, and the tempo card.
    var surface: Color
    var hairline: Color
    /// The eraser at rest is an outline with no fill, and wants a border it
    /// can be seen by.
    var outline: Color
    var label: Color
    var pillLabel: Color
    /// The tempo card's edge, which the design draws harder than a hairline.
    var cardEdge: Color

    /// The inset glow under a raised control. A control that is on or being
    /// pressed swaps this colour and keeps everything else.
    var bloom: Color
    /// The eraser, while it is on.
    var eraseBloom: Color
    /// The shuffle, for as long as a finger is down on it.
    var shuffleBloom: Color

    /// Dimmed while the eraser owns the screen.
    var dimmed: Double

    /// The ground the mixer's panels lie on, a shade off the sequencer's.
    /// One field fills the screen and is the screen; four cards need
    /// something to be lying on, or they read as holes cut in it.
    var mixerGround: UInt32

    var background: Color { Color(hex: ground) }

    /// The same palette, standing on the mixer's ground.
    var opened: SequencerPalette {
        var copy = self
        copy.ground = mixerGround
        return copy
    }

    /// The same ground, for Metal. The field's texture is `.bgra8Unorm`,
    /// which is shown as written, so these are the sRGB values themselves and
    /// not a linear conversion of them — convert, and the field would sit a
    /// visibly different shade from the bars above and below it.
    var clearColor: MTLClearColor {
        MTLClearColor(
            red: Double((ground >> 16) & 0xFF) / 255,
            green: Double((ground >> 8) & 0xFF) / 255,
            blue: Double(ground & 0xFF) / 255,
            alpha: 1)
    }

    /// The screen as designed.
    static let dark = SequencerPalette(
        ground: 0x000000,
        surface: Color(hex: 0x101010),
        hairline: Color.white.opacity(0.07),
        outline: Color.white.opacity(0.2),
        label: .white,
        pillLabel: Color(hex: 0xF5F3F3),
        cardEdge: .black,
        bloom: Color(hex: 0x2B2B2B),
        eraseBloom: .red,
        shuffleBloom: Color(hex: 0xFF66E0),
        dimmed: 0.3,
        mixerGround: 0x1C1C1C
    )

    /// The same screen turned over, for looking at the field on paper rather
    /// than in the dark. Every part keeps its job — the surface is still a
    /// shade off the ground, the hairline is still barely there — so the
    /// greys are inverted rather than chosen again, and the eraser's red and
    /// the shuffle's pink stay put, because those are the design's colours
    /// rather than its greys.
    static let light = SequencerPalette(
        ground: 0xF2F0EE,
        surface: .white,
        hairline: Color.black.opacity(0.08),
        outline: Color.black.opacity(0.18),
        label: Color(hex: 0x111111),
        pillLabel: Color(hex: 0x1A1A1A),
        cardEdge: Color.black.opacity(0.1),
        bloom: Color(hex: 0xD9D5D1),
        eraseBloom: .red,
        shuffleBloom: Color(hex: 0xFF66E0),
        dimmed: 0.3,
        mixerGround: 0xE7E4E1
    )
}

private struct SequencerPaletteKey: EnvironmentKey {
    static let defaultValue = SequencerPalette.dark
}

extension EnvironmentValues {
    /// Which ground this part of the screen is standing on. Set once, at the
    /// top of the sequencer.
    var sequencerPalette: SequencerPalette {
        get { self[SequencerPaletteKey.self] }
        set { self[SequencerPaletteKey.self] = newValue }
    }
}


extension Color {
    /// 0xRRGGBB in sRGB — the form the CSS is written in, so the two can be
    /// read side by side.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
