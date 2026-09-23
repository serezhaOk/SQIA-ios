// The profile, pushed from the library's account button.
//
// Three glass cards on the library's backdrop, from the Figma frame: whether
// the sound carries on once the app is out of sight; feedback and a rating;
// and the documents, each of which opens in the browser. The account itself
// — logging out, deleting it — is behind the header's menu, one step further
// from a thumb than anything on the cards.

import SQIACore
import SwiftUI
import StoreKit

struct ProfileView: View {
    var accountEmail: String?
    var onSignOut: @MainActor () async -> Void
    var onDeleteAccount: @MainActor () async -> Void

    @AppStorage(Preferences.backgroundPlayback) private var playsInBackground = false
    @State private var closingAccount = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        GeometryReader { geometry in
            let width = LibraryLayout.cardWidth(screen: Double(geometry.size.width))
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .frame(width: width)
                        .padding(.top, LibraryLayout.headTop)
                    VStack(spacing: LibraryLayout.gap) {
                        card(width: width) { playbackRow }
                        card(width: width) {
                            row("Leave feedback", icon: .pencilIcon) { openURL(Self.feedback) }
                            row("Rate in App Store", icon: .likeIcon) { requestReview() }
                        }
                        card(width: width) {
                            row("Privacy policy", icon: .openInNewIcon) { openURL(Self.privacy) }
                            row("Terms of use", icon: .openInNewIcon) { openURL(Self.terms) }
                            row("About", icon: .openInNewIcon) { openURL(Self.about) }
                        }
                    }
                    .padding(.top, ProfileLayout.cardsTop)
                    .padding(.bottom, LibraryLayout.gap)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ProgressiveBlur()
                        .frame(height: LibraryLayout.blurHeight)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(LibraryBackdrop(isEmpty: false))
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBack())
        .confirmationDialog(
            "Delete your account?", isPresented: $closingAccount, titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await onDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every project goes with it. This cannot be undone.")
        }
    }

    // -------------------------------------------------------------- header --

    private var header: some View {
        ZStack {
            Text("Profile")
                .manrope(.bold, TextStyle.titleSize, tracking: -0.03)
                .foregroundStyle(Palette.ui)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    roundIcon(.backIcon)
                }
                .buttonStyle(PillPress())
                .accessibilityLabel("Back")
                Spacer(minLength: 8)
                accountMenu
            }
        }
        .frame(height: LibraryLayout.headHeight)
    }

    private var accountMenu: some View {
        Menu {
            Section(accountEmail ?? "Signed in") {
                Button("Log out") { Task { await onSignOut() } }
                // Guideline 5.1.1(v): an account made in the app has to be
                // closable from the app.
                Button("Delete account", role: .destructive) { closingAccount = true }
            }
        } label: {
            roundIcon(.detailIcon)
        }
        .accessibilityLabel("Account")
    }

    private func roundIcon(_ icon: ImageResource) -> some View {
        Image(icon)
            .frame(width: LibraryLayout.headHeight, height: LibraryLayout.headHeight)
            .background(Palette.glassButton, in: Circle())
            .contentShape(Circle())
    }

    // --------------------------------------------------------------- cards --

    private static let cardShape = RoundedRectangle(
        cornerRadius: LibraryLayout.cornerRadius, style: .continuous)

    /// A card's rows sit 24 apart and 24 in from its top and bottom. Each row
    /// is given half of that above and below as its own, so the whole band is
    /// a target rather than just the 23 points of its label.
    private func card<Rows: View>(width: Double, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(spacing: 0) { rows() }
            .padding(.horizontal, ProfileLayout.rowInset)
            .padding(.vertical, ProfileLayout.rowGap / 2)
            .frame(width: width)
            .background(Palette.glass, in: Self.cardShape)
            .overlay(Self.cardShape.strokeBorder(Palette.glassEdge, lineWidth: 1))
    }

    private var playbackRow: some View {
        Toggle(isOn: $playsInBackground) {
            label("Background playback")
        }
        .tint(Palette.toggleOn)
        .padding(.vertical, ProfileLayout.rowGap / 2)
    }

    private func row(
        _ title: String, icon: ImageResource, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label(title)
                Spacer(minLength: 0)
                Image(icon)
            }
            .padding(.vertical, ProfileLayout.rowGap / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .manrope(.semibold, TextStyle.rowSize, tracking: -0.02)
            .foregroundStyle(Palette.ui)
    }

    // --------------------------------------------------------------- links --

    private static let privacy = URL(string: "https://sqia.serezhaok.com/privacy.html")!
    private static let terms = URL(string: "https://sqia.serezhaok.com/terms.html")!
    private static let about = URL(string: "https://serezhaok.com")!

    /// Feedback opens the mail app rather than a form behind someone else's
    /// script, because the privacy manifest says nothing here talks to anyone
    /// but this project's own Supabase, and that has to stay true.
    ///
    /// The build goes in the body because it is the first thing any report
    /// needs and the last thing anyone knows offhand. Two blank lines above
    /// it, so what the person came to write goes at the top and the numbers
    /// stay underneath. `URLComponents` is what does the percent-encoding:
    /// written out as a string literal, the spaces and newlines would have
    /// to be escaped by hand and a missed one returns nil.
    private static var feedback: URL {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = "serezhaok@gmail.com"
        mail.queryItems = [
            URLQueryItem(name: "subject", value: "SQIA: Feedback"),
            URLQueryItem(name: "body", value: "\n\nSQIA \(version) (\(build))"),
        ]
        return mail.url!
    }
}

/// From the Figma frame. Everything else is the library's.
private enum ProfileLayout {
    /// Header to the first card: 134 in the mockup, less the header's 56 + 48.
    static let cardsTop = 30.0
    static let rowInset = 20.0
    static let rowGap = 24.0
}

/// A row dims while it is held — the card behind it stays put.
private struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Hiding the navigation bar takes the edge swipe back with it, and a
/// pushed screen that cannot be swiped away is one the thumb keeps trying.
/// This puts the swipe back: the stack's own pop gesture, allowed whenever
/// there is something to pop to.
private struct SwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Enabler { Enabler() }
    func updateUIViewController(_ controller: Enabler, context: Context) {}

    final class Enabler: UIViewController, UIGestureRecognizerDelegate {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
