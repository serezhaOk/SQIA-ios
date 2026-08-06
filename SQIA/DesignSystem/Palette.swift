// The palette, straight from the web app's style.css.
//
// SQIA is a black app with one near-white ink and a handful of greys; there
// is no light mode and no system colour anywhere, so these are plain sRGB
// values rather than semantic colours that would shift under us.

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

    // Landing
    static let tagline = Color(hex: 0xCFCFCF)
    static let muted = Color(hex: 0x8A8A8A)
    static let link = Color(hex: 0xB9B9B9)
    static let copyright = Color(hex: 0x6A6A6A)
    static let fieldBackground = Color(hex: 0x0F0F0F)
    static let fieldBorder = Color(hex: 0x3A3A3A)
    static let fieldBorderFocused = Color(hex: 0x8A8A8A)
    static let placeholder = Color(hex: 0x6F6F6F)
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

    // Landing logo
    static let logoStroke = Color(hex: 0x4A4A4A)
    static let logoDot = Color(hex: 0xD9D9D9)
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
