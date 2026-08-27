// The app opens, and every screen can be reached from every other.
//
// This is the one thing the core suite cannot say anything about. Two
// hundred and seventy-eight tests prove the pitch mapping, the envelopes,
// the reverb tail and the session policy, and all of them would still pass
// if a view were wired to the wrong model and the library never appeared.
//
// So this walks the app: library → a project → the mixer → back. It asserts
// on accessibility labels rather than on pixels, which means it doubles as a
// check that VoiceOver has something to read on every screen — the two
// failures look the same from here, and both are worth failing on.
//
// It gets in through `-uiTesting`, which swaps the Supabase store for rows
// in memory and skips the sign-in screen. The web's suites do the same thing
// through `__showProjects` and `__setRows`, for the same reason: a smoke
// test that needed a network and a real account would be testing the network
// and the account.

import XCTest

final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    /// How long to give a screen. Generous: a simulator on a loaded CI runner
    /// is slow in a way a phone is not, and a flaky smoke test is worse than
    /// none because it teaches people to re-run rather than look.
    private let patience: TimeInterval = 20

    /// Anything with this label, whatever kind of element SwiftUI decided to
    /// make it. Which of `buttons`, `staticTexts` or `otherElements` a given
    /// modifier produces is not a thing worth asserting on, and is not stable
    /// across OS versions either.
    private func named(_ label: String) -> XCUIElement {
        // `firstMatch`, because a label is not unique: the field calls
        // itself "Tracks" while the mixer is open and the header button
        // does too, and an ambiguous query fails rather than picking one.
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    @discardableResult
    private func awaitElement(_ label: String, _ message: String) -> XCUIElement {
        let element = named(label)
        XCTAssertTrue(element.waitForExistence(timeout: patience), message)
        return element
    }

    /// Straight to the sequencer with a project open, which four of the five
    /// tests want before they can start.
    private func openAProject() {
        awaitElement("Wild Amoeba", "the library never appeared").tap()
        awaitElement("Note field", "the sequencer's field is unnamed or never appeared")
    }

    func testTheLibraryOpensWithItsProjects() {
        awaitElement("Projects", "the library never appeared")
        XCTAssertTrue(named("Wild Amoeba").exists)
        XCTAssertTrue(named("Slow Diatom").exists)
        XCTAssertTrue(named("Account").exists, "the account menu has no label")
    }

    func testOpeningAProjectReachesTheSequencer() {
        // The field is the biggest thing on the screen and used to have no
        // name at all; `openAProject` fails if that regresses.
        openAProject()

        // The controls, by the labels VoiceOver reads.
        //
        // These were ERASE and RNDM while the two of them were words on the
        // screen. The design makes them icons, and an icon has no text to
        // fall back on — so the label is the only name either one has now,
        // and asserting on it is worth more than it was before, not less.
        XCTAssertTrue(named("Tempo").exists)
        XCTAssertTrue(named("Tracks").exists)
        XCTAssertTrue(named("Erase").exists)
        XCTAssertTrue(named("Shuffle").exists)
        XCTAssertTrue(named("Sound").exists)
    }

    func testTheMixerOpensAndComesBackToTheLibrary() {
        openAProject()
        awaitElement("Tracks", "the track dots are missing").tap()
        awaitElement("Back to projects", "the mixer did not open, or its way out is missing")
            .tap()
        awaitElement("Projects", "leaving the mixer did not return to the library")
    }

    func testTheSoundSheetOpensAndCloses() {
        openAProject()
        awaitElement("Sound", "the voice label is unlabelled").tap()
        awaitElement("Done", "the sound sheet did not open").tap()
        awaitElement("Note field", "the sheet did not close")
    }

    /// Drawing is the app. If a drag on the field crashes the renderer or the
    /// audio thread, it happens here rather than in somebody's hands.
    func testDrawingOnTheFieldDoesNotFallOver() {
        openAProject()
        let field = named("Note field")

        let from = field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
        let to = field.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
        from.press(forDuration: 0.05, thenDragTo: to)

        // A second or so of it actually playing what was drawn, and then the
        // app is still there — which is the whole assertion. A renderer or an
        // audio thread that falls over does it in about this long.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(app.state, .runningForeground, "the app went away while playing")
        XCTAssertTrue(named("Tracks").exists)
    }
}
