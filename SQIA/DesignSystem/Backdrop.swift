// The library's surfaces, shared with the screens that open off it: the
// blurred forest behind them and the blur the bottom of the screen goes
// soft under.

import SwiftUI
import UIKit

/// Behind the library and the profile: the login's forest, out of focus. Laid out on the
/// mockup's 375-wide frame and scaled with the screen, so a bigger phone
/// sees the same picture rather than more of it.
///
/// With projects it is a darker grade of the still at full strength; with
/// none it is the login's own still at 0.3 with a dark pool at the bottom,
/// so the one card on the screen is the brightest thing on it. Both are
/// blurred once and flattened, and the scroll moves over them without
/// asking for either again.
struct LibraryBackdrop: View {
    var isEmpty: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 375
            ZStack(alignment: .top) {
                Color.black
                Image(.libraryBackdrop)
                    .resizable()
                    .frame(width: 792 * scale, height: 1051 * scale)
                    .blur(radius: 48.25 * scale)
                    .offset(y: -99 * scale)
                    .opacity(isEmpty ? 0 : 1)
                ZStack(alignment: .topLeading) {
                    Image(.loginStill)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 642 * scale, height: 853 * scale)
                        .clipped()
                    RoundedRectangle(cornerRadius: 60 * scale)
                        .fill(Color(hex: 0x0B110C))
                        .frame(width: 436 * scale, height: 199 * scale)
                        .blur(radius: 45.5 * scale)
                        .offset(x: 103 * scale, y: 654 * scale)
                }
                .frame(width: 642 * scale, height: 853 * scale)
                .blur(radius: 35.45 * scale)
                .opacity(isEmpty ? 0.3 : 0)
                .offset(y: -21 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
            .drawingGroup()
        }
        .ignoresSafeArea()
        .animation(Motion.fade, value: isEmpty)
        .accessibilityHidden(true)
    }
}

/// Blur that builds towards the bottom edge: nothing at the top of the band,
/// all of it at the bottom. The design's is a plain blur with no tint, and
/// every material iOS offers carries one — over this backdrop it read as a
/// grey bar laid across the bottom of the screen. So this is the system's
/// blur with the tint layers above it hidden, and a ramp for a mask is what
/// makes it progressive.
struct ProgressiveBlur: View {
    var body: some View {
        UntintedBlur()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.7), location: 0.55),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
    }
}

struct UntintedBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> BlurOnly { BlurOnly() }
    func updateUIView(_ view: BlurOnly, context: Context) {}

    /// The first subview of an effect view is the blur of what is behind it;
    /// the ones above it are the material's tint and the content view. Only
    /// public views are touched, and if the arrangement ever changes the
    /// worst case is the tint coming back, not a crash.
    final class BlurOnly: UIVisualEffectView {
        init() {
            super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            for view in subviews.dropFirst() { view.isHidden = true }
        }
    }
}
