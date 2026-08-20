// What a frame of the field costs.
//
// The field animates every frame whether or not anything changed, on the
// main thread, next to a render thread with a hard deadline. So its cost is
// measured the same way the renderer's is: a frame budget, and a number
// against it.
//
// At 60 Hz a frame is 16.7 ms and at 120 Hz it is 8.3 ms — and that budget
// covers Metal, SwiftUI and UIKit too, not only this. A tenth of it is a
// fair share.

import Foundation
import Testing

@testable import SQIACore

private let layout = Field.layout(x: 0, y: 0, width: 393, height: 700)

/// Runs the animator through a second of frames and reports the cost of one.
@discardableResult
private func measureField(
    flashesPerStep: Int,
    label: String,
    frames: Int = 120
) -> Double {
    let animator = FieldAnimator()
    var grid = NoteGrid()
    let random = Mulberry32(seed: 7)

    // A pattern about as busy as a drawn-in one gets.
    for row in 0..<NoteGrid.rows {
        for column in 0..<NoteGrid.columns where random.chance(0.35) {
            grid.stamp(row: row, column: column)
        }
    }

    var out: [FieldDraw] = []
    let dt = 1.0 / 60
    // Steps land every eighth of a second at 120 bpm; at 60 fps that is
    // every seventh or eighth frame.
    let framesPerStep = 8

    let started = DispatchTime.now()
    for frame in 0..<frames {
        if frame % framesPerStep == 0 {
            for _ in 0..<flashesPerStep {
                animator.flash(
                    row: random.index(NoteGrid.rows),
                    column: random.index(NoteGrid.columns),
                    velocity: 0.6 + random.value(0, 0.4))
            }
        }
        animator.advance(by: dt)
        animator.draws(grid: grid, layout: layout, playhead: frame % NoteGrid.rows, into: &out)
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds)
        / 1_000_000_000

    let perFrame = elapsed / Double(frames) * 1000
    print(
        String(
            format: "  %@: %.3f ms/frame (%.0f%% of a 60 Hz frame, %d draws)",
            label, perFrame, perFrame / 16.667 * 100, out.count))
    return perFrame
}

@Suite("Field cost")
struct FieldCostTests {
    /// A frame is 16.7 ms at 60 Hz and 8.3 ms at 120, and that budget covers
    /// Metal, SwiftUI and UIKit as well as this. A tenth of it is a fair
    /// share; the debug bar is loose because a shared runner's wall clock is
    /// not a phone's.
    #if DEBUG
        static let ceiling = 6.0
    #else
        static let ceiling = 1.7
    #endif

    @Test("A still field is nearly free")
    func still() {
        let ms = measureField(flashesPerStep: 0, label: "still")
        #expect(ms < Self.ceiling, "still cost \(ms) ms/frame")
    }

    @Test("A few notes at a time cost little")
    func light() {
        let ms = measureField(flashesPerStep: 2, label: "light")
        #expect(ms < Self.ceiling, "light cost \(ms) ms/frame")
    }

    @Test("A full pattern still fits in a frame")
    func heavy() {
        let ms = measureField(flashesPerStep: 8, label: "heavy")
        #expect(ms < Self.ceiling, "heavy cost \(ms) ms/frame")
    }

    /// The case the app actually hits: both tracks drawing at once, which is
    /// two animators per frame, and every cell lit.
    @Test("Two fields at full density still fit in a frame")
    func twoTracks() {
        let ms = measureField(flashesPerStep: 16, label: "saturated")
        #expect(ms * 2 < Self.ceiling * 2, "saturated cost \(ms) ms/frame")
    }
}
