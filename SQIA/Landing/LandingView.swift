// The front door.
//
// Built from the Figma frame (281:8721) rather than from the web app: a
// looping film, the wordmark a quarter of the way down, and two round
// buttons near the bottom. Every number in `Metrics` is that frame's, on the
// 393x852 canvas it was drawn on. The only one that is a fraction rather
// than a distance is the wordmark's top, so the composition still holds on a
// phone shorter than the one it was drawn for; the bottom cluster hangs off
// the bottom edge, which is where the design measures it from too.
//
// Two ways in, not three. Email is gone for now. Apple goes first because
// Guideline 4.8 asks for it wherever Google is offered, and at the same
// size, which the design already gives it.

import SQIACore
import SwiftUI

struct LandingView: View {
    let auth: AuthController

    @Environment(\.scenePhase) private var scenePhase
    @State private var ambience = LoginAmbience()

    private enum Metrics {
        /// The canvas everything below was measured on.
        static let canvas: CGFloat = 852

        static let wordmarkTop: CGFloat = 211 / canvas
        static let wordmark = CGSize(width: 230.54, height: 121.85)
        static let wordmarkToTagline: CGFloat = 21

        static let promptToButtons: CGFloat = 24
        static let button = CGSize(width: 114, height: 52)
        static let betweenButtons: CGFloat = 10
        /// The design's icon slot, straight from the frame. The Figma marks
        /// carry their own padding inside it and ours are drawn tight to
        /// their boxes, so at this size ours read a touch larger than the
        /// mock's rendered glyph — which is the size the frame asks for.
        static let mark: CGFloat = 21.43

        static let buttonsToTerms: CGFloat = 50
        static let bottomInset: CGFloat = 32
        static let bannerToPrompt: CGFloat = 20
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LoginBackdrop(isPlaying: scenePhase == .active)

                wordmark
                    .padding(.top, proxy.size.height * Metrics.wordmarkTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                doors
                    .padding(.horizontal, 24)
                    .padding(.bottom, Metrics.bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(Palette.background)
        .ignoresSafeArea()
        .onAppear { ambience.start() }
        .onDisappear { ambience.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ambience.start()
            } else {
                ambience.stop()
            }
        }
    }

    // --------------------------------------------------------- the wordmark --

    private var wordmark: some View {
        VStack(spacing: Metrics.wordmarkToTagline) {
            Image(.loginWordmark)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.wordmark.width, height: Metrics.wordmark.height)
                .accessibilityLabel("SQIA")

            Text("Built for sound accidents")
                .manrope(.regular, TextStyle.taglineSize, tracking: 0)
                .foregroundStyle(Palette.loginTagline)
                .multilineTextAlignment(.center)
        }
    }

    // ------------------------------------------------------------- the doors --

    private var doors: some View {
        // Bottom-anchored, so a message that appears grows the column
        // upwards and every distance the design measures from the bottom
        // edge stays what it was.
        VStack(spacing: 0) {
            if let message = auth.message {
                banner(message)
                    .padding(.bottom, Metrics.bannerToPrompt)
            }

            Text("Continue with")
                .manrope(.medium, TextStyle.promptSize, tracking: 0)
                .foregroundStyle(.white)

            HStack(spacing: Metrics.betweenButtons) {
                appleDoor
                googleDoor
            }
            .padding(.top, Metrics.promptToButtons)

            terms
                .padding(.top, Metrics.buttonsToTerms)
        }
    }

    private var appleDoor: some View {
        door({ auth.signInWithApple() }) {
            // Apple's own glyph, from the system, which is the only mark
            // Apple allows on a button that signs somebody in with it.
            Image(systemName: "apple.logo")
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.mark, height: Metrics.mark)
                .foregroundStyle(.black)
        }
        .accessibilityLabel("Continue with Apple")
    }

    private var googleDoor: some View {
        door({ auth.signInWithGoogle() }) {
            GoogleMark().frame(width: Metrics.mark, height: Metrics.mark)
        }
        .accessibilityLabel("Continue with Google")
    }

    /// The white pill both ways in are drawn on. `Capsule` rather than a
    /// 100-point radius, which is what the design's `corner-radius/l` means
    /// on a shape 52 tall.
    private func door<Mark: View>(
        _ act: @escaping () -> Void, @ViewBuilder mark: () -> Mark
    ) -> some View {
        Button(action: act) {
            mark()
                .frame(width: Metrics.button.width, height: Metrics.button.height)
                .background(.white, in: Capsule())
        }
        .buttonStyle(PillPress())
        .opacity(auth.isWorking ? 0.6 : 1)
        .disabled(auth.isWorking)
    }

    // -------------------------------------------------------------- the rest --

    private var terms: some View {
        // One run of text with two links inside it, the way the design draws
        // it — not three views pretending to be a sentence. The markdown is
        // a literal because an interpolated one is not parsed.
        Text(
            """
            by continuing you agree to our \
            [Terms](https://sqia.serezhaok.com/terms.html) and \
            [Privacy Policy](https://sqia.serezhaok.com/privacy.html)
            """
        )
        .manrope(.regular, TextStyle.termsSize, tracking: 0)
        .foregroundStyle(Palette.loginTerms)
        .tint(.white)
        .multilineTextAlignment(.center)
    }

    private func banner(_ message: AuthController.Message) -> some View {
        Text(message.text)
            .manrope(.regular, TextStyle.messageSize)
            .foregroundStyle(message.isError ? Palette.failure : Palette.success)
            .multilineTextAlignment(.center)
            // Legible over whatever frame of the film is underneath it.
            .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
    }
}

/// Google's mark, from the four paths in the web app's markup.
private struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 48
            for (colour, path) in Self.paths {
                var scaled = Path()
                scaled.addPath(path, transform: .init(scaleX: s, y: s))
                context.fill(scaled, with: .color(Color(hex: colour)))
            }
        }
        .accessibilityHidden(true)
    }

    /// The same four shapes, as Béziers on the 48-point box.
    private static let paths: [(UInt32, Path)] = [
        (
            0xEA4335,
            path {
                $0.move(to: CGPoint(x: 24, y: 9.5))
                $0.addCurve(
                    to: CGPoint(x: 33, y: 13.1), control1: CGPoint(x: 27.5, y: 9.5),
                    control2: CGPoint(x: 30.6, y: 10.7))
                $0.addLine(to: CGPoint(x: 39.7, y: 6.4))
                $0.addCurve(
                    to: CGPoint(x: 24, y: 0), control1: CGPoint(x: 35.6, y: 2.6),
                    control2: CGPoint(x: 30.2, y: 0))
                $0.addCurve(
                    to: CGPoint(x: 2.6, y: 13.2), control1: CGPoint(x: 14.6, y: 0),
                    control2: CGPoint(x: 6.5, y: 5.4))
                $0.addLine(to: CGPoint(x: 10.4, y: 19.3))
                $0.addCurve(
                    to: CGPoint(x: 24, y: 9.5), control1: CGPoint(x: 12.3, y: 13.1),
                    control2: CGPoint(x: 17.7, y: 9.5))
            }
        ),
        (
            0x4285F4,
            path {
                $0.move(to: CGPoint(x: 46.1, y: 24.6))
                $0.addCurve(
                    to: CGPoint(x: 45.7, y: 20), control1: CGPoint(x: 46.1, y: 23),
                    control2: CGPoint(x: 46, y: 21.5))
                $0.addLine(to: CGPoint(x: 24, y: 20))
                $0.addLine(to: CGPoint(x: 24, y: 29.1))
                $0.addLine(to: CGPoint(x: 36.4, y: 29.1))
                $0.addCurve(
                    to: CGPoint(x: 31.7, y: 36.1), control1: CGPoint(x: 35.9, y: 32),
                    control2: CGPoint(x: 34.2, y: 34.5))
                $0.addLine(to: CGPoint(x: 39.3, y: 42))
                $0.addCurve(
                    to: CGPoint(x: 46.1, y: 24.6), control1: CGPoint(x: 43.7, y: 37.9),
                    control2: CGPoint(x: 46.1, y: 31.9))
            }
        ),
        (
            0xFBBC05,
            path {
                $0.move(to: CGPoint(x: 10.4, y: 28.7))
                $0.addCurve(
                    to: CGPoint(x: 9.6, y: 24), control1: CGPoint(x: 9.9, y: 27.3),
                    control2: CGPoint(x: 9.6, y: 25.8))
                $0.addCurve(
                    to: CGPoint(x: 10.4, y: 19.3), control1: CGPoint(x: 9.6, y: 22.2),
                    control2: CGPoint(x: 9.9, y: 20.7))
                $0.addLine(to: CGPoint(x: 2.6, y: 13.2))
                $0.addCurve(
                    to: CGPoint(x: 0, y: 24), control1: CGPoint(x: 1, y: 16.3),
                    control2: CGPoint(x: 0, y: 20))
                $0.addCurve(
                    to: CGPoint(x: 2.6, y: 34.8), control1: CGPoint(x: 0, y: 28),
                    control2: CGPoint(x: 1, y: 31.7))
                $0.addLine(to: CGPoint(x: 10.4, y: 28.7))
            }
        ),
        (
            0x34A853,
            path {
                $0.move(to: CGPoint(x: 24, y: 48))
                $0.addCurve(
                    to: CGPoint(x: 39.9, y: 42.2), control1: CGPoint(x: 30.5, y: 48),
                    control2: CGPoint(x: 35.9, y: 45.9))
                $0.addLine(to: CGPoint(x: 32.3, y: 36.3))
                $0.addCurve(
                    to: CGPoint(x: 24, y: 38.6), control1: CGPoint(x: 30.2, y: 37.7),
                    control2: CGPoint(x: 27.5, y: 38.6))
                $0.addCurve(
                    to: CGPoint(x: 10.4, y: 29.7), control1: CGPoint(x: 17.7, y: 38.6),
                    control2: CGPoint(x: 12.3, y: 35))
                $0.addLine(to: CGPoint(x: 2.6, y: 35.8))
                $0.addCurve(
                    to: CGPoint(x: 24, y: 48), control1: CGPoint(x: 6.5, y: 42.6),
                    control2: CGPoint(x: 14.6, y: 48))
            }
        ),
    ]

    private static func path(_ build: (inout Path) -> Void) -> Path {
        var path = Path()
        build(&path)
        path.closeSubpath()
        return path
    }
}

#Preview {
    LandingView(auth: AuthController(storage: InMemorySessionStorage()))
}
