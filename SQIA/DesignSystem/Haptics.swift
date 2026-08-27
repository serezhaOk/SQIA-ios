// What the controls feel like.
//
// Three weights, and the difference between them is what they are reporting.
// A tap is the lightest thing that still registers. Turning the eraser on is
// a mode change and gets something you notice. The tempo wheel is a run of
// selections, which iOS has its own generator for — used as intended, it
// paces itself across a fast drag instead of firing a hundred taps.
//
// The generators are held rather than made per call: a fresh one has to warm
// the Taptic Engine up, and the first buzz of a drag arrives late enough to
// feel disconnected from the finger.

import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .soft)
    private static let firm = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()

    /// Called before a gesture that is about to produce a run of feedback,
    /// so the engine is awake when the first one lands.
    static func warm() {
        light.prepare()
        firm.prepare()
        selection.prepare()
    }

    /// Any ordinary press.
    static func tap() {
        light.impactOccurred()
    }

    /// A mode going on or off — the eraser, the mixer.
    static func toggle() {
        firm.impactOccurred()
    }

    /// One step of a wheel or a scrub.
    static func step() {
        selection.selectionChanged()
    }
}
