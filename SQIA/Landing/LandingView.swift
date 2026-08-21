// The front door.
//
// Metrics are the web app's: the mark at 132, the wordmark at 2.6rem, the
// buttons 54 tall and fully rounded, 38 points of air above the first one
// and 12 between the rest, and the whole column capped at 340 and centred.
//
// One button the web does not have. Guideline 4.8 requires Apple sign-in
// wherever Google is offered, and requires it be no less prominent — so it
// goes first, in Apple's own button, at the same size as the rest.

import AuthenticationServices
import SQIACore
import SwiftUI

struct LandingView: View {
    let auth: AuthController

    @State private var showingEmail = false
    @State private var email = ""
    @FocusState private var emailFocused: Bool

    private static let buttonHeight: CGFloat = 54
    private static let column: CGFloat = 340

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SQIALogo()
                    .frame(width: 132, height: 132)
                    .padding(.bottom, 26)

                Text("SQIA")
                    .manrope(.bold, TextStyle.wordmarkSize, tracking: -0.02)
                    .foregroundStyle(Palette.ui)

                Text("Built for sound accidents")
                    .manrope(.regular, TextStyle.taglineSize)
                    .foregroundStyle(Palette.tagline)
                    .padding(.top, 10)

                appleButton.padding(.top, 38)
                googleButton.padding(.top, 12)
                emailButton.padding(.top, 12)
                if showingEmail { emailForm.padding(.top, 12) }

                terms.padding(.top, 18)
                if let message = auth.message { banner(message).padding(.top, 16) }

                Link("What is SQIA?", destination: Self.about)
                    .manrope(.regular, TextStyle.aboutSize)
                    .foregroundStyle(Palette.logoDot)
                    .underline()
                    .padding(.top, 46)

                Text("© 2026 Sergei Diuzhev. All rights reserved.")
                    .manrope(.regular, TextStyle.copyrightSize)
                    .foregroundStyle(Palette.copyright)
                    .padding(.top, 28)
            }
            .frame(maxWidth: Self.column)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background.ignoresSafeArea())
    }

    // ------------------------------------------------------------- buttons --

    private var appleButton: some View {
        SignInWithAppleButton(
            .continue,
            onRequest: { auth.prepareAppleRequest($0) },
            onCompletion: { auth.handleApple($0) }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: Self.buttonHeight)
        .clipShape(Capsule())
        .disabled(auth.isWorking)
    }

    private var googleButton: some View {
        Button {
            auth.signInWithGoogle()
        } label: {
            HStack(spacing: 10) {
                GoogleMark().frame(width: 20, height: 20)
                Text("Continue with Google")
                    .manrope(.semibold, TextStyle.buttonSize)
            }
            .foregroundStyle(Color(hex: 0x111111))
            .frame(maxWidth: .infinity)
            .frame(height: Self.buttonHeight)
            .background(Palette.ui, in: Capsule())
        }
        .buttonStyle(PillPress())
        .opacity(auth.isWorking ? 0.6 : 1)
        .disabled(auth.isWorking)
    }

    /// The dark one: its label sits left, not centred, as the CSS has it.
    private var emailButton: some View {
        Button {
            showingEmail = true
            emailFocused = true
        } label: {
            Text("Continue with email")
                .manrope(.semibold, TextStyle.buttonSize)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                .frame(height: Self.buttonHeight)
                .background(Palette.fieldBackground, in: Capsule())
                .overlay(Capsule().stroke(Palette.fieldBorder, lineWidth: 1))
        }
        .buttonStyle(PressFade())
        .disabled(auth.isWorking)
    }

    private var emailForm: some View {
        VStack(spacing: 10) {
            TextField("", text: $email, prompt: placeholder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($emailFocused)
                .manrope(.regular, TextStyle.buttonSize)
                .foregroundStyle(Palette.ui)
                .padding(.horizontal, 24)
                .frame(height: Self.buttonHeight)
                .background(Palette.fieldBackground, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        emailFocused ? Palette.fieldBorderFocused : Palette.fieldBorder,
                        lineWidth: 1)
                )
                .onSubmit(send)

            Button(action: send) {
                Text("Send sign-in link")
                    .manrope(.semibold, TextStyle.buttonSize)
                    .foregroundStyle(Color(hex: 0x111111))
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.buttonHeight)
                    .background(Palette.ui, in: Capsule())
            }
            .buttonStyle(PillPress())
            .opacity(auth.isWorking ? 0.6 : 1)
            .disabled(auth.isWorking)
        }
    }

    private var placeholder: Text {
        Text("example@email.com")
            .font(Manrope.regular.font(TextStyle.buttonSize))
            .foregroundColor(Palette.placeholder)
    }

    private func send() {
        emailFocused = false
        auth.sendMagicLink(to: email)
    }

    // -------------------------------------------------------------- the rest --

    private static let about = URL(
        string: "https://www.instagram.com/reel/Dbh7eVJAed7/?igsh=MTJ2MzQxaGZtNm81dw==")!

    private var terms: some View {
        // One run of text with two links inside it, which is what the web
        // has — not three views pretending to be a sentence. The markdown
        // is a literal because an interpolated one is not parsed.
        Text(
            """
            By continuing, you agree to our \
            [Terms](https://sqia.serezhaok.com/terms.html) and \
            [Privacy Policy](https://sqia.serezhaok.com/privacy.html).
            """
        )
        .manrope(.regular, TextStyle.termsSize)
        .foregroundStyle(Palette.muted)
        .tint(Palette.link)
        .multilineTextAlignment(.center)
    }

    private func banner(_ message: AuthController.Message) -> some View {
        Text(message.text)
            .manrope(.regular, TextStyle.messageSize)
            .foregroundStyle(message.isError ? Palette.failure : Palette.success)
            .multilineTextAlignment(.center)
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
