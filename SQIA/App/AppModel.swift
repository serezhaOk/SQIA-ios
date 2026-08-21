// Which screen is up, and the one audio engine underneath both.
//
// The sequencer's model is built the first time a project opens and then
// kept, which is what the web's `ensureAudio()` does: starting an audio
// engine is expensive and doing it again on every trip back from the library
// would be heard. Opening a project is also the gesture iOS wants before it
// will let anything make a sound, so the engine could not start earlier
// anyway.

import Foundation
import SQIACore
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Screen {
        case library
        case sequencer
    }

    private(set) var screen = Screen.library
    let library: LibraryModel
    /// Nil until a project has been opened for the first time.
    private(set) var sequencer: SequencerModel?

    @ObservationIgnored private let store: any ProjectStore
    /// Signing in is M8; until then the account pill has nothing to show.
    private(set) var accountEmail: String?

    init(store: any ProjectStore = FileProjectStore()) {
        self.store = store
        library = LibraryModel(store: store)
    }

    func open(_ project: Project) {
        let model = engine()
        model.open(project)
        screen = .sequencer
        model.start()
    }

    /// A new project: a blank field first, so the app is playable at once,
    /// and the row written behind it. If that write fails there is still a
    /// field to draw on — the next edit will find no row and simply not
    /// save, which is the web's behaviour when it is offline.
    func createNew() {
        let model = engine()
        model.startFresh()
        screen = .sequencer
        model.start()
        Task {
            if let created = await library.create(model.snapshot) {
                model.adopt(created)
            }
        }
    }

    /// The flush happens before the screen changes, so the library redraws
    /// from rows that include what was just played. Reloading them is the
    /// library screen's own `.task`, which runs when it comes back.
    func backToLibrary() async {
        await sequencer?.leave()
        screen = .library
    }

    func signOut() {
        // M8.
        accountEmail = nil
    }

    private func engine() -> SequencerModel {
        if let sequencer { return sequencer }
        let model = SequencerModel(store: store)
        sequencer = model
        return model
    }
}
