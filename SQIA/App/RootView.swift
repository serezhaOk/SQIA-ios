// The app's root: the sign-in screen, the library, the sequencer.
//
// Which one is up follows the session. Coming back to an app that was signed
// in goes straight to the library — the cached sign-in is read from the
// Keychain before anything is asked of the network, and before anything is
// drawn, so there is no flash of a sign-in screen for somebody who never
// signed out. That read is a few milliseconds; the black it shows while it
// happens is the launch screen's own colour, so nothing appears to blink.

import SQIACore
import SwiftUI

struct RootView: View {
    @State private var app = AppModel()

    var body: some View {
        ZStack {
            if app.hasStarted {
                switch app.screen {
                case .landing:
                    LandingView(auth: app.auth)
                        .transition(.opacity)
                case .library:
                    LibraryView(
                        model: app.library,
                        accountEmail: app.accountEmail,
                        onOpen: { app.open($0) },
                        onCreate: { app.createNew() },
                        onSignOut: { await app.signOut() },
                        onDeleteAccount: { await app.deleteAccount() }
                    )
                    .transition(.opacity)
                case .sequencer:
                    if let sequencer = app.sequencer {
                        SequencerView(
                            model: sequencer,
                            onLeave: { await app.backToLibrary() }
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: app.screen)
        .task { await app.start() }
        // Google's browser and the mailed link both come back this way.
        .onOpenURL { url in Task { await app.open(url) } }
        .onChange(of: app.auth.isSignedIn) { _, signedIn in
            app.sessionChanged(to: signedIn)
        }
    }
}

#Preview {
    RootView()
}
