// The library.
//
// Metrics are the web app's, from style.css: the four-dot mark and the
// account pill 35 points down, the title at 44 over a 60-point line, cards
// in two columns with a 7-point gutter and 20-point margins, the create pill
// pinned 40 above the home indicator. Above 768 points the cards stop
// stretching and become fixed 200-point tiles, centred.
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
    var onOpen: (Project) -> Void
    var onCreate: () -> Void
    var onSignOut: @MainActor () async -> Void
    var onDeleteAccount: @MainActor () async -> Void

    @State private var renaming: Project?
    @State private var renameText = ""
    @State private var deleting: Project?
    @State private var closingAccount = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let grid = LibraryLayout.layout(width: width)
            ScrollView {
                VStack(spacing: 0) {
                    header
                    title
                    list(grid)
                    // Room for the pill, which floats over the scroll.
                    Color.clear.frame(
                        height: LibraryLayout.createBottom + LibraryLayout.createHeight + 24)
                }
            }
            .overlay(alignment: .bottom) { createPill(width) }
            .overlay(alignment: .bottom) { failureBanner }
        }
        // A delete takes the card off before the store has answered, and a
        // refusal puts it back; without this both are a hole that opens in
        // the grid between one frame and the next. Keyed on the rows rather
        // than wrapped round each call, so a reload that reorders them
        // moves the cards too.
        .animation(Motion.settle(reduced: reduceMotion), value: model.rows)
        .animation(Motion.fade, value: model.failure)
        .background(Palette.background.ignoresSafeArea())
        .task { await model.load() }
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
            FourDotMark()
                .frame(width: LibraryLayout.headHeight, height: LibraryLayout.headHeight)
            Spacer(minLength: 8)
            accountMenu
        }
        .frame(height: LibraryLayout.headHeight)
        .padding(.horizontal, LibraryLayout.margin)
        .padding(.top, LibraryLayout.headTop)
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
            Image(systemName: "face.smiling")
                .font(.system(size: 22))
                .foregroundStyle(Palette.ui)
                .frame(width: LibraryLayout.profile.width, height: LibraryLayout.profile.height)
                .background(Palette.card, in: Capsule())
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

    private var title: some View {
        Text("Projects")
            .manrope(.medium, TextStyle.titleSize, tracking: -0.03)
            .foregroundStyle(Palette.ui)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .padding(.top, LibraryLayout.titleTop)
    }

    // --------------------------------------------------------------- cards --

    @ViewBuilder
    private func list(_ grid: (columns: Int, side: Double)) -> some View {
        if model.isEmpty {
            emptyCard
                .padding(.horizontal, LibraryLayout.margin)
                .padding(.top, LibraryLayout.listTop)
        } else {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(grid.side), spacing: LibraryLayout.gap, alignment: .top),
                    count: grid.columns),
                spacing: LibraryLayout.gap
            ) {
                ForEach(model.rows) { project in
                    card(project, side: grid.side)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, LibraryLayout.listTop)
        }
    }

    private func card(_ project: Project, side: Double) -> some View {
        Button {
            onOpen(project)
        } label: {
            Text(project.name)
                .manrope(.medium, TextStyle.cardNameSize)
                .foregroundStyle(Palette.ui)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(LibraryLayout.cardPadding)
                .frame(width: side, height: side)
                .background(
                    Palette.card,
                    in: RoundedRectangle(cornerRadius: LibraryLayout.cornerRadius))
        }
        .buttonStyle(CardPress())
        .overlay(alignment: .topTrailing) { cardMenu(project) }
        .transition(Motion.arrive)
        .accessibilityLabel(project.name)
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
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .medium))
                .rotationEffect(.degrees(90))
                .foregroundStyle(Palette.icon)
                // The glyph is 24 points and sits 20 in from the top and
                // right, so its centre is 32 in from both. The tap target
                // around it is 48, which puts its own centre at 24 — the
                // offset is the difference, and the finger gets the bigger
                // of the two.
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .offset(x: -8, y: 8)
        }
        .accessibilityLabel("Actions for \(project.name)")
    }

    private var emptyCard: some View {
        Button(action: onCreate) {
            Text("+ Create first project")
                .manrope(.medium, TextStyle.cardNameSize)
                .foregroundStyle(Palette.ui)
                .frame(maxWidth: .infinity)
                .frame(height: LibraryLayout.emptyHeight)
                .background(
                    Palette.card,
                    in: RoundedRectangle(cornerRadius: LibraryLayout.cornerRadius))
        }
        .buttonStyle(CardPress())
        .transition(Motion.arrive)
    }

    // ---------------------------------------------------------- the create --

    /// Full width between 24-point insets on a phone; the width of one tile,
    /// centred, once the cards have stopped stretching.
    @ViewBuilder
    private func createPill(_ width: Double) -> some View {
        if !model.isEmpty {
            Button(action: onCreate) {
                Text("+ Create new")
                    .manrope(.semibold, TextStyle.menuItemSize)
                    .foregroundStyle(Color(hex: 0x111111))
                    .frame(
                        maxWidth: width >= LibraryLayout.breakpoint
                            ? LibraryLayout.tile : .infinity
                    )
                    .frame(height: LibraryLayout.createHeight)
                    .background(Palette.ui, in: Capsule())
            }
            .buttonStyle(PillPress())
            .padding(.horizontal, LibraryLayout.createInset)
            .padding(.bottom, LibraryLayout.createBottom)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var failureBanner: some View {
        if let failure = model.failure {
            Text(failure)
                .manrope(.regular, TextStyle.messageSize)
                .foregroundStyle(Palette.failure)
                .padding(12)
                .padding(.bottom, LibraryLayout.createBottom + LibraryLayout.createHeight)
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

/// The four-dot mark in the library's header — the field going away, which
/// is the same idea as the app icon at a size where dots are all it can be.
private struct FourDotMark: View {
    /// diameter, opacity, per the CSS
    private static let dots: [(CGFloat, Double)] = [(12, 1), (7, 0.75), (7, 0.55), (5, 0.4)]

    var body: some View {
        GeometryReader { geometry in
            let cell = geometry.size.width / 2
            ForEach(0..<4, id: \.self) { index in
                let (size, alpha) = Self.dots[index]
                Circle()
                    .fill(Palette.ui)
                    .opacity(alpha)
                    .frame(width: size, height: size)
                    .position(
                        x: cell * (0.5 + CGFloat(index % 2)),
                        y: cell * (0.5 + CGFloat(index / 2)))
            }
        }
        .accessibilityHidden(true)
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
