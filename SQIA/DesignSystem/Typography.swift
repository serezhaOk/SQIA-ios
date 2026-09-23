// Manrope, at the sizes and letter-spacings the web app uses.
//
// The four weights ship as static instances (tools/make-fonts.py) because
// the variable file's default instance is ExtraLight — asking for the family
// by name would quietly give a weight the design never uses.
//
// CSS letter-spacing is in em and SwiftUI tracking is in points, so every
// style carries its own tracking already multiplied out.

import SwiftUI

enum Manrope: String {
    case regular = "Manrope-Regular"
    case medium = "Manrope-Medium"
    case semibold = "Manrope-SemiBold"
    case bold = "Manrope-Bold"

    func font(_ size: CGFloat) -> Font {
        .custom(rawValue, size: size)
    }
}

extension View {
    /// A Manrope style with letter-spacing given the way the CSS gives it.
    func manrope(_ weight: Manrope, _ size: CGFloat, tracking em: CGFloat = -0.01) -> some View {
        font(weight.font(size)).tracking(size * em)
    }
}

enum TextStyle {
    // Sign-in. These come from the Figma frame rather than the web app's
    // CSS, so they are whole points and carry no letter-spacing.
    static let taglineSize: CGFloat = 17
    static let promptSize: CGFloat = 17
    static let termsSize: CGFloat = 13
    static let messageSize: CGFloat = 13.6  // 0.85rem

    // Projects, from the Figma frame like the sign-in. The name is set
    // 40 apart at 35, tighter than Manrope's own 48, so two lines of it
    // read as one title rather than as a paragraph.
    static let titleSize: CGFloat = 24
    static let cardNameSize: CGFloat = 35
    static let cardNameLineHeight: CGFloat = 40
    static let cardDetailSize: CGFloat = 15
    static let menuItemSize: CGFloat = 15
    /// A row on the profile's cards.
    static let rowSize: CGFloat = 17

    // Sequencer — wide tracking is the look here, so it is spelled out.
    static let labelSize: CGFloat = 13.1  // 0.82rem
    static let labelTracking: CGFloat = 0.14
    static let voiceLabelTracking: CGFloat = 0.12
}
