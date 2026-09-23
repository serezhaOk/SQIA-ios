// The library.
//
// Metrics are the Figma frame's rather than the web's style.css now: a
// "My vibes" header with a round account button, then one column of tall
// glass cards over a blurred still of the login's forest — name, tempo and
// key, and a play pill that plays the project's loop without opening it. The create pill is a fixed 175 wide, 40 off the
// bottom edge of the screen, and the list goes under a blur on its way
// past it.
//
// What is not the web's is the modals. A web context menu is a positioned
// div and a rename is `prompt()`; here they are a Menu, an alert with a text
// field, and a confirmation dialog, because those are the ones the phone
// already knows how to animate, dismiss, and read aloud.

import SQIACore
import SwiftUI

struct LibraryView: View {
    let model: LibraryModel
    var accountEmail: String?
    /// The project whose loop is playing from here, if any.
    var previewing: String?
    var onOpen: (Project) -> Void
    var onPreview: (Project) -> Void
    var onStopPreview: () -> Void
    var onCreate: () -> Void
    var onSignOut: @MainActor () async -> Void
    var onDeleteAccount: @MainActor () async -> Void

    @State private var renaming: Project?
    @State private var renameText = ""
    @State private var deleting: Project?
    @State private var closingAccount = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let width = LibraryLayout.cardWidth(screen: Double(geometry.size.width))
            let bottomInset = Double(geometry.safeAreaInsets.bottom)
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .frame(width: width)
                        .padding(.top, LibraryLayout.headTop)
                    list(width: width, emptyHeight: emptyHeight(geometry))
                        .padding(.top, LibraryLayout.listTop)
                    // Room for the pill, which floats over the scroll.
                    if !model.isEmpty {
                        Color.clear.frame(
                            height: max(
                                0,
                                LibraryLayout.createBottom + LibraryLayout.createHeight
                                    + LibraryLayout.gap - bottomInset))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay {
                // Measured from the screen's edge, so the stack is let out
                // past the home indicator and the band pushed down to it.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bottomBlur
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .bottom) { createPill(bottomInset: bottomInset) }
            .overlay(alignment: .bottom) { failureBanner(bottomInset: bottomInset) }
        }
        // A delete takes the card off before the store has answered, and a
        // refusal puts it back; without this both are a hole that opens in
        // the grid between one frame and the next. Keyed on the rows rather
        // than wrapped round each call, so a reload that reorders them
        // moves the cards too.
        .animation(Motion.settle(reduced: reduceMotion), value: model.rows)
        .animation(Motion.fade, value: model.failure)
        .background(LibraryBackdrop(isEmpty: model.isEmpty))
        .task { await model.load() }
        // A loop plays while somebody is here listening to it. Leaving the
        // app ends it, as it does in the sequencer, and deleting the card
        // that is playing takes its sound with it.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { onStopPreview() }
        }
        .onChange(of: model.rows) { _, rows in
            if let previewing, !rows.contains(where: { $0.id == previewing }) {
                onStopPreview()
            }
        }
        // Both of these take the row through `presenting:` rather than
        // reading it back out of state inside the action. The binding is
        // cleared as part of dismissing, and an action that went looking
        // for the project afterwards would sometimes find nothing.
        .alert("Project name", isPresented: renamingBinding, presenting: renaming) { project in
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = renameText
                Task { await model.rename(id: project.id, to: name) }
            }
        }
        .confirmationDialog(
            deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: deletingBinding, titleVisibility: .visible, presenting: deleting
        ) { project in
            Button("Delete", role: .destructive) {
                Task { await model.delete(id: project.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This cannot be undone.")
        }
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
        HStack(spacing: 0) {
            Text("My vibes")
                .manrope(.bold, TextStyle.titleSize, tracking: -0.03)
                .foregroundStyle(Palette.ui)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            accountMenu
        }
        .frame(height: LibraryLayout.headHeight)
    }

    private var accountMenu: some View {
        Menu {
            Link("Leave feedback", destination: Self.feedback)
            Section(accountEmail ?? "Signed in") {
                Button("Log out") { Task { await onSignOut() } }
                // Guideline 5.1.1(v): an account made in the app has to be
                // closable from the app.
                Button("Delete account", role: .destructive) { closingAccount = true }
            }
        } label: {
            Image(.userIcon)
                .frame(width: LibraryLayout.headHeight, height: LibraryLayout.headHeight)
                .background(Palette.glassButton, in: Circle())
        }
        .accessibilityLabel("Account")
    }

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

    // --------------------------------------------------------------- cards --

    /// What is left of the screen under the header, down to 20 off its
    /// bottom edge — the empty card is the whole of it.
    private func emptyHeight(_ geometry: GeometryProxy) -> Double {
        let bottom = max(
            0, LibraryLayout.emptyBottom - Double(geometry.safeAreaInsets.bottom))
        return max(
            LibraryLayout.cardHeight,
            Double(geometry.size.height) - LibraryLayout.headTop - LibraryLayout.headHeight
                - LibraryLayout.listTop - bottom)
    }

    @ViewBuilder
    private func list(width: Double, emptyHeight: Double) -> some View {
        if model.isEmpty {
            emptyCard(width: width, height: emptyHeight)
        } else {
            LazyVStack(spacing: LibraryLayout.gap) {
                ForEach(model.rows) { project in
                    card(project, width: width)
                }
            }
            .frame(width: width)
        }
    }

    /// Two targets on one card: the card opens the project, the pill plays
    /// it where it is. A button inside a button's label is not something
    /// SwiftUI resolves reliably, so the card's own button is only the
    /// glass, and what is drawn on it lets touches through to it — all but
    /// the pill.
    private func card(_ project: Project, width: Double) -> some View {
        let playing = previewing == project.id
        return ZStack {
            Button {
                onOpen(project)
            } label: {
                Palette.glass
                    .clipShape(Self.cardShape)
                    .overlay(Self.cardShape.strokeBorder(Palette.glassEdge, lineWidth: 1))
                    .contentShape(Self.cardShape)
            }
            .buttonStyle(CardPress())
            .accessibilityLabel(project.name)
            .accessibilityValue("\(project.bpm) bpm, \(Self.key(of: project))")

            VStack(spacing: 0) {
                Group {
                    Text(project.name)
                        .manrope(.semibold, TextStyle.cardNameSize, tracking: -0.02)
                        .lineSpacing(Self.cardNameLineSpacing)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        // 30 in from either side; the menu glyph sits in the
                        // corner above, clear of a two-line name.
                        .frame(width: max(0, width - 60))
                    HStack(spacing: 16) {
                        Text("\(project.bpm) bpm")
                        Text(Self.key(of: project))
                    }
                    .manrope(.regular, TextStyle.cardDetailSize, tracking: 0.01)
                    .opacity(0.5)
                    .padding(.top, 8)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                playButton(project, playing: playing)
                    .padding(.top, 34)
            }
            .foregroundStyle(Palette.ui)
        }
        .frame(width: width, height: LibraryLayout.cardHeight)
        .overlay(alignment: .topTrailing) { cardMenu(project) }
        .transition(Motion.arrive)
    }

    private func playButton(_ project: Project, playing: Bool) -> some View {
        Button {
            Haptics.tap()
            onPreview(project)
        } label: {
            ZStack {
                if playing {
                    // The design draws only the play glyph; stop is the
                    // system's, at the weight and size that sits beside it.
                    Image(systemName: "pause.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Image(.playIcon)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 72, height: 48)
            .background(Palette.playButton, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.playButtonEdge, lineWidth: 0.5))
            .contentShape(Capsule())
            .animation(Motion.fade, value: playing)
        }
        .buttonStyle(PillPress())
        .accessibilityLabel(playing ? "Stop \(project.name)" : "Play \(project.name)")
    }

    private static let cardShape = RoundedRectangle(
        cornerRadius: LibraryLayout.cornerRadius, style: .continuous)

    /// Manrope's own line is about 48 at 35; the design sets two lines of
    /// the name 40 apart, and SwiftUI takes a negative spacing to get there.
    private static let cardNameLineSpacing: CGFloat = {
        let font = UIFont(name: Manrope.semibold.rawValue, size: TextStyle.cardNameSize)
        return TextStyle.cardNameLineHeight - (font?.lineHeight ?? TextStyle.cardNameLineHeight)
    }()

    /// "A# minor" — the root the way the key sheet names it, then the scale.
    private static func key(of project: Project) -> String {
        let root = Music.noteNames[min(max(project.rootPc, 0), Music.noteNames.count - 1)]
        return "\(root) \(project.scale)"
    }

    private func cardMenu(_ project: Project) -> some View {
        Menu {
            Button {
                renameText = project.name
                renaming = project
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleting = project
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(.moreIcon)
                // The glyph is 24 points and sits 24 in from the top and
                // right, so its centre is 36 in from both. The tap target
                // around it is 48, which puts its own centre at 24 — the
                // offset is the difference, and the finger gets the bigger
                // of the two.
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .offset(x: -12, y: 12)
        }
        .accessibilityLabel("Actions for \(project.name)")
    }

    private func emptyCard(width: Double, height: Double) -> some View {
        Button(action: onCreate) {
            Text("+ Create first project")
                .manrope(.semibold, TextStyle.menuItemSize, tracking: 0.01)
                .foregroundStyle(Palette.ui)
                .frame(width: width, height: height)
                .background(Palette.glass, in: Self.cardShape)
                .overlay(Self.cardShape.strokeBorder(Palette.glassEdge, lineWidth: 1))
                .contentShape(Self.cardShape)
        }
        .buttonStyle(CardPress())
        .transition(Motion.arrive)
    }

    // ---------------------------------------------------------- the create --

    @ViewBuilder
    private func createPill(bottomInset: Double) -> some View {
        if !model.isEmpty {
            Button(action: onCreate) {
                Text("+ Create new")
                    .manrope(.semibold, TextStyle.menuItemSize, tracking: 0.01)
                    .foregroundStyle(Color.black)
                    .frame(width: LibraryLayout.createWidth, height: LibraryLayout.createHeight)
                    .background(Palette.ui, in: Capsule())
            }
            .buttonStyle(PillPress())
            .padding(.bottom, max(0, LibraryLayout.createBottom - bottomInset))
            .transition(.opacity)
        }
    }

    /// The list does not run into the pill; it goes soft on its way under.
    @ViewBuilder
    private var bottomBlur: some View {
        if !model.isEmpty {
            ProgressiveBlur()
                .frame(height: LibraryLayout.blurHeight)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func failureBanner(bottomInset: Double) -> some View {
        if let failure = model.failure {
            Text(failure)
                .manrope(.regular, TextStyle.messageSize)
                .foregroundStyle(Palette.failure)
                .padding(12)
                .padding(
                    .bottom,
                    max(0, LibraryLayout.createBottom + LibraryLayout.createHeight - bottomInset))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // ------------------------------------------------------------ bindings --

    /// An alert takes a Bool; what the screen has is which project. Setting
    /// it false is the dismissal, and that is the only write these accept.
    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

/// Behind the library: the login's forest, out of focus. Laid out on the
/// mockup's 375-wide frame and scaled with the screen, so a bigger phone
/// sees the same picture rather than more of it.
///
/// With projects it is a darker grade of the still at full strength; with
/// none it is the login's own still at 0.3 with a dark pool at the bottom,
/// so the one card on the screen is the brightest thing on it. Both are
/// blurred once and flattened, and the scroll moves over them without
/// asking for either again.
private struct LibraryBackdrop: View {
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
private struct ProgressiveBlur: View {
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

private struct UntintedBlur: UIViewRepresentable {
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

/// A card lightens while it is held, as `:active` does.
struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The light pill darkens instead.
struct PillPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
