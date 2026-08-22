// Which screen is up, the one audio engine underneath, and the session
// everything else hangs off.
//
// The sequencer's model is built the first time a project opens and then
// kept, which is what the web's `ensureAudio()` does: starting an audio
// engine is expensive and doing it again on every trip back from the library
// would be heard. Opening a project is also the gesture iOS wants before it
// will let anything make a sound, so the engine could not start earlier
// anyway.
//
// The project store is built once and asks for a token per call, so it does
// not need rebuilding when somebody signs in — it simply starts working.

import Foundation
import SQIACore
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Screen {
        case landing
        case library
        case sequencer
    }

    private(set) var screen = Screen.landing
    let auth: AuthController
    let library: LibraryModel
    /// Nil until a project has been opened for the first time.
    private(set) var sequencer: SequencerModel?

    @ObservationIgnored private let store: any ProjectStore
    /// True once a session has taken us past the sign-in screen. Losing one
    /// after that is what sends the user back; not having one before it is
    /// just the starting state.
    @ObservationIgnored private var wasSignedIn = false

    /// Built here rather than as a default argument: a default is evaluated
    /// outside the main actor, and `AuthController` lives on it.
    init(auth: AuthController? = nil) {
        #if DEBUG
            // The smoke test's way in. The web has the same seam — its suites
            // call `__showProjects` and `__setRows` — and for the same
            // reason: a test that needed a network and a real account would
            // be testing the network and the account.
            if Self.isUITesting {
                let store = InMemoryProjectStore(
                    random: Mulberry32(seed: 4), seeded: Self.fixtures)
                self.auth = auth ?? AuthController(storage: InMemorySessionStorage())
                self.store = store
                library = LibraryModel(store: store)
                return
            }
        #endif
        let auth = auth ?? AuthController()
        self.auth = auth
        let keeper = auth.keeper
        store = SupabaseProjectStore(session: { await keeper.supabaseSession() })
        library = LibraryModel(store: store)
    }

    #if DEBUG
        static var isUITesting: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTesting")
        }

        /// Two rows, so the library has something to draw and the test has
        /// something to tap. Named rather than random: an assertion cannot
        /// look for a name nobody knows.
        private static let fixtures: [Project] = [
            Project(
                id: "fixture-wild", name: "Wild Amoeba", bpm: 120, rootPc: 9,
                scale: "minor", tracks: [], updatedAt: "2026-08-21T12:00:00Z"),
            Project(
                id: "fixture-slow", name: "Slow Diatom", bpm: 96, rootPc: 4,
                scale: "dorian", tracks: [], updatedAt: "2026-08-20T12:00:00Z"),
        ]
    #endif

    var accountEmail: String? { auth.session?.user.email }

    // ------------------------------------------------------------ the door --

    func start() async {
        #if DEBUG
            if Self.isUITesting {
                wasSignedIn = true
                screen = .library
                return
            }
        #endif
        await auth.start()
        if auth.isSignedIn {
            wasSignedIn = true
            screen = .library
        }
    }

    /// A session means the library; losing one means the sign-in screen, and
    /// whatever reason the keeper wrote down goes with it.
    func sessionChanged(to signedIn: Bool) {
        guard auth.hasSettled else { return }
        if signedIn {
            wasSignedIn = true
            if screen == .landing { screen = .library }
        } else if wasSignedIn {
            wasSignedIn = false
            sequencer?.stop()
            screen = .landing
        }
    }

    func open(_ url: URL) async {
        await auth.handle(url)
    }

    // ------------------------------------------------------------ projects --

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

    // ------------------------------------------------------------ the exit --

    func signOut() async {
        await sequencer?.leave()
        await auth.signOut()
        sessionChanged(to: false)
    }

    /// Guideline 5.1.1(v). Everything goes: `projects` and `profiles` both
    /// cascade from the account row.
    func deleteAccount() async {
        await sequencer?.leave()
        if await auth.deleteAccount() {
            sessionChanged(to: false)
        }
    }

    private func engine() -> SequencerModel {
        if let sequencer { return sequencer }
        let model = SequencerModel(store: store)
        sequencer = model
        return model
    }
}
