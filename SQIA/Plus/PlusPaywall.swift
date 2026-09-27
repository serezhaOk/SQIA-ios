// The paywall, from the Figma frame "Paywall": a dark green sheet with two
// pale green glows bleeding in from its edges and vines creeping in at the
// bottom corners, the app's icon in a wreath of them, what Plus opens as a
// column of pills, and one white Subscribe button.
//
// The sheet itself is the system's — its corners, its grabber, its swipe to
// dismiss, and Restore as a navigation bar button — with no close button:
// swiping down is the way out.
//
// It used to be StoreKit's `SubscriptionStoreView`. The design wants the
// whole sheet, so the buying is ours now: `PlusStore` does the purchase and
// the restore, and this screen carries what App Review looks for on a
// subscription — the name, the price and its period from the storefront,
// Restore, and the privacy and terms links.

import SQIACore
import SwiftUI

struct PlusPaywall: View {
    let plus: PlusStore

    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            content
                .background {
                    GeometryReader { geometry in
                        ZStack {
                            PaywallLayout.ground
                            vines(in: geometry.size)
                            glows(in: geometry.size)
                        }
                    }
                    .ignoresSafeArea()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Restore") { run(plus.restore) }
                            .disabled(busy)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(.white)
        .presentationBackground(PaywallLayout.ground)
        .presentationDragIndicator(.visible)
        .task { await plus.loadProduct() }
        .onChange(of: plus.access.hasPlus) { _, hasPlus in
            // A restore, or a purchase that finished on another device
            // while this was open.
            if hasPlus { dismiss() }
        }
    }

    // ------------------------------------------------------------- content --

    private var content: some View {
        VStack(spacing: 0) {
            PaywallIcon()
                .padding(.top, 8)

            Text("Access all features")
                .manrope(.medium, 20, tracking: 0)
                .foregroundStyle(.white)
                .padding(.top, 64)

            VStack(spacing: 4) {
                FeaturePill(
                    symbol: "square.split.2x1", text: "Play two sequences simultaneously")
                FeaturePill(symbol: "headphones", text: "Listen with background playback")
                FeaturePill(symbol: nil, text: "...more features are coming")
            }
            .padding(.top, 24)

            Text(priceLine)
                .manrope(.medium, 20, tracking: 0)
                .foregroundStyle(.white)
                .padding(.top, 68)

            Spacer(minLength: 16)

            if let message {
                Text(message)
                    .manrope(.regular, 13, tracking: 0)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }

            subscribeButton
                .padding(.horizontal, 16)

            footer
                .padding(.horizontal, 40)
                .padding(.top, 14)
                // The home indicator's inset is already under it.
                .padding(.bottom, 4)
        }
        .animation(Motion.fade, value: message)
    }

    /// The storefront's own price, so it reads in the buyer's currency. The
    /// design's "/m." is spelled out: the period is part of what 3.1.2 asks
    /// to be clear.
    private var priceLine: String {
        guard let product = plus.product else { return " " }
        return "for \(product.displayPrice)/month"
    }

    private var subscribeButton: some View {
        Button {
            run(plus.purchase)
        } label: {
            ZStack {
                Text("Subscribe")
                    .manrope(.medium, 17, tracking: 0)
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView().tint(.black)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(.white, in: Capsule())
        }
        .buttonStyle(PressFade())
        .disabled(busy || plus.product == nil)
        .accessibilityValue(priceLine)
        .accessibilityIdentifier("paywall.subscribe")
    }

    private var footer: some View {
        HStack(spacing: 16) {
            link("Privacy", Links.privacy)
            link("Terms", Links.terms)
            Spacer(minLength: 8)
            Text("Cancel anytime")
                .manrope(.regular, 12, tracking: 0)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(title)
                .manrope(.regular, 12, tracking: 0)
                .underline()
                .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(PressFade())
    }

    /// One purchase or restore at a time, and whatever it ended in said
    /// under the button — except a cancel, which somebody chose.
    private func run(_ action: @escaping () async -> PlusStore.Outcome) {
        guard !busy else { return }
        busy = true
        message = nil
        Task {
            let outcome = await action()
            busy = false
            switch outcome {
            case .subscribed:
                Haptics.toggle()
                dismiss()
            case .pending:
                message = "Waiting for approval. Plus opens as soon as it comes through."
            case .cancelled:
                break
            case .failed(let reason):
                message = reason
            }
        }
    }

    // --------------------------------------------------------------- glows --

    /// The same vine twice, turned 41°, creeping in over the bottom left
    /// and the bottom right. Exclusion rather than plain over, as the frame
    /// sets it, so the dark stems lift out of the green instead of sitting
    /// on it as black.
    private func vines(in size: CGSize) -> some View {
        ZStack {
            vine(side: 280)
                .position(x: -60.5, y: size.height - 185.5)
            vine(side: 328.6)
                .position(x: size.width + 40.5, y: size.height - 135.5)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func vine(side: CGFloat) -> some View {
        Image(.paywallVines)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .rotationEffect(.degrees(41.13))
            .blendMode(.exclusion)
    }

    /// Two shapes blurred into light, each turned 45° and mostly off the
    /// sheet: one over the upper left, one over the lower right. Set
    /// against the sheet's edges rather than its middle, as the frame does.
    private func glows(in size: CGSize) -> some View {
        ZStack {
            PaywallGlow(shape: .upperLeft)
                .position(x: -129, y: 257)
            PaywallGlow(shape: .lowerRight)
                .position(x: size.width + 92, y: size.height - 166)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// ------------------------------------------------------------------ parts --

/// From the Figma frame.
private enum PaywallLayout {
    static let ground = Color(hex: 0x1A221A)
    static let glow = Color(hex: 0xBEE2B9)
    static let pill = Color.black.opacity(0.3)
}

/// The small white tag the profile marks what Plus opens with.
struct PlusBadge: View {
    var body: some View {
        Text("Plus")
            .manrope(.semibold, 13, tracking: 0.07)
            .textCase(.uppercase)
            .foregroundStyle(.black.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct FeaturePill: View {
    let symbol: String?
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(hex: 0xE3E3E3))
                    .frame(width: 20, height: 20)
            }
            Text(text)
                .manrope(.regular, 15, tracking: 0)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, symbol == nil ? 20 : 10)
        .padding(.vertical, 8)
        .background(PaywallLayout.pill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The app's icon, cut to the frame's corner with its hairline and the
/// white glow along its inside top edge, in its wreath of vines.
private struct PaywallIcon: View {
    private static let size: CGFloat = 160.26
    private static let corner: CGFloat = 46.27
    private static let edge = Color(hex: 0x6E9265)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        Image(.plusIcon)
            .resizable()
            .interpolation(.high)
            .frame(width: Self.size, height: Self.size)
            .clipShape(shape)
            // The design's `inset 0 4px 15px rgba(255,255,255,0.8)`: a stroke
            // pushed down and blurred, then clipped back inside the shape.
            .overlay {
                shape
                    .stroke(.white.opacity(0.8), lineWidth: 13.5)
                    .blur(radius: 8.5)
                    .offset(y: 4.5)
                    .mask { shape }
                    .allowsHitTesting(false)
            }
            .overlay { shape.strokeBorder(Self.edge, lineWidth: 1.13) }
            // Hung over the icon a touch up and to the left of its centre,
            // and wider than it: the wreath takes no room of its own.
            .overlay {
                Image(.paywallWreath)
                    .resizable()
                    .frame(width: 316, height: 316)
                    .offset(x: -5.6, y: -3.4)
                    .allowsHitTesting(false)
            }
            // The name is on the icon; this is what VoiceOver reads first.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("SQIA Plus")
            .accessibilityAddTraits(.isHeader)
    }
}

/// One of the frame's two glows: its shape, filled and blurred by the
/// frame's 106, inside a 318 square turned 45°.
private struct PaywallGlow: View {
    enum Glow {
        case lowerRight, upperLeft
    }

    let shape: Glow
    private static let margin: CGFloat = 320

    var body: some View {
        Canvas { context, _ in
            context.addFilter(.blur(radius: 106))
            // The SVG's own coordinates, less where the frame puts the
            // square inside it, plus the margin.
            context.translateBy(
                x: Self.margin + (shape == .lowerRight ? -161.93 : -170.89),
                y: Self.margin - 212)
            context.fill(path, with: .color(PaywallLayout.glow))
        }
        // The 318 square with room all round for the blur, which a Canvas
        // would otherwise cut at its edges. Same centre either way.
        .frame(width: 318 + 2 * Self.margin, height: 318 + 2 * Self.margin)
        .rotationEffect(.degrees(-45))
    }

    private var path: Path {
        var path = Path()
        switch shape {
        case .lowerRight:
            path.move(to: CGPoint(x: 283.841, y: 274.335))
            path.addCurve(
                to: CGPoint(x: 298.852, y: 212), control1: CGPoint(x: 253.002, y: 258.568),
                control2: CGPoint(x: 264.216, y: 212))
            path.addLine(to: CGPoint(x: 419.919, y: 212))
            path.addCurve(
                to: CGPoint(x: 479.919, y: 272), control1: CGPoint(x: 453.056, y: 212),
                control2: CGPoint(x: 479.919, y: 238.863))
            path.addLine(to: CGPoint(x: 479.919, y: 470))
            path.addCurve(
                to: CGPoint(x: 419.919, y: 530), control1: CGPoint(x: 479.919, y: 503.137),
                control2: CGPoint(x: 453.056, y: 530))
            path.addLine(to: CGPoint(x: 272.098, y: 530))
            path.addCurve(
                to: CGPoint(x: 221.697, y: 437.447), control1: CGPoint(x: 224.571, y: 530),
                control2: CGPoint(x: 195.911, y: 477.371))
            path.addLine(to: CGPoint(x: 296.53, y: 321.586))
            path.addCurve(
                to: CGPoint(x: 283.841, y: 274.335), control1: CGPoint(x: 307.123, y: 305.185),
                control2: CGPoint(x: 301.225, y: 283.223))
        case .upperLeft:
            path.move(to: CGPoint(x: 219.445, y: 300.792))
            path.addCurve(
                to: CGPoint(x: 272.085, y: 212), control1: CGPoint(x: 197.575, y: 260.808),
                control2: CGPoint(x: 226.511, y: 212))
            path.addLine(to: CGPoint(x: 428.879, y: 212))
            path.addCurve(
                to: CGPoint(x: 488.879, y: 272), control1: CGPoint(x: 462.016, y: 212),
                control2: CGPoint(x: 488.879, y: 238.863))
            path.addLine(to: CGPoint(x: 488.879, y: 432.949))
            path.addCurve(
                to: CGPoint(x: 402.062, y: 486.622), control1: CGPoint(x: 488.879, y: 477.544),
                control2: CGPoint(x: 441.955, y: 506.555))
            path.addLine(to: CGPoint(x: 307.442, y: 439.346))
            path.addCurve(
                to: CGPoint(x: 281.619, y: 414.465), control1: CGPoint(x: 296.499, y: 433.879),
                control2: CGPoint(x: 287.489, y: 425.197))
            path.addLine(to: CGPoint(x: 219.445, y: 300.792))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PlusPaywall(plus: PlusStore())
        }
}
