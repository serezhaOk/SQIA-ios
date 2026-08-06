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
    // Landing
    static let wordmarkSize: CGFloat = 41.6  // 2.6rem
    static let taglineSize: CGFloat = 16
    static let buttonSize: CGFloat = 16
    static let termsSize: CGFloat = 12.5  // 0.78rem
    static let messageSize: CGFloat = 13.6  // 0.85rem
    static let aboutSize: CGFloat = 14.4  // 0.9rem
    static let copyrightSize: CGFloat = 11.5  // 0.72rem

    // Projects
    static let titleSize: CGFloat = 44
    static let cardNameSize: CGFloat = 15
    static let menuItemSize: CGFloat = 15

    // Sequencer — wide tracking is the look here, so it is spelled out.
    static let labelSize: CGFloat = 13.1  // 0.82rem
    static let labelTracking: CGFloat = 0.14
    static let voiceLabelTracking: CGFloat = 0.12
}
