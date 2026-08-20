// The app's root.
//
// The sequencer is the whole app for now. The sign-in screen and the project
// library come with M7 and M8, and this is where the routing between them
// will live.

import SwiftUI

struct RootView: View {
    var body: some View {
        SequencerView()
    }
}

#Preview {
    RootView()
}
