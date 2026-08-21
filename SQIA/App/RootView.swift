// The app's root: the sign-in screen, the library, the sequencer.
//
// Which one is up follows the session. Coming back to an app that was signed
// in goes straight to the library — the cached sign-in is read from the
// Keychain before anything is asked of the network, so there is no flash of
// a sign-in screen for somebody who never signed out.

import SQIACore
import SwiftUI

struct RootView: View {
    @State private var app = AppModel()

    var body: some View {
        ZStack {
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
