// The app's root.
//
// Two screens: the library and the sequencer. The sign-in screen in front of
// both of them comes with M8.

import SQIACore
import SwiftUI

struct RootView: View {
    @State private var app = AppModel()

    var body: some View {
        ZStack {
            switch app.screen {
            case .library:
                LibraryView(
                    model: app.library,
                    accountEmail: app.accountEmail,
                    onOpen: { app.open($0) },
                    onCreate: { app.createNew() },
                    onSignOut: { app.signOut() }
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
    }
}

#Preview {
    RootView()
}
