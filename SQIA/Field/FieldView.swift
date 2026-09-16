// The field, on screen.
//
// An MTKView driving `FieldRenderer` at the display's own rate. The field
// animates every frame whether or not anything changed — it breathes, and
// blooms decay — so there is no point asking SwiftUI to redraw it.

import MetalKit
import SQIACore
import SwiftUI
import UIKit

/// The state one field draws from. A class so the renderer can read the
/// current values each frame without SwiftUI having to push them.
@MainActor
final class FieldScene {
    var grid = NoteGrid()
    /// Row currently sounding, or −1.
    var playhead = -1
    var detail: Double = 1
    var alpha: Double = 1
    /// How this field is drawn. One place, because the model has to hand the
    /// same one to `Field.layout` when it works out what a finger touched.
    var style: FieldStyle = .heat
    let animator = FieldAnimator()

    init(grid: NoteGrid = NoteGrid()) {
        self.grid = grid
    }

    /// A note just sounded here.
    func flash(row: Int, column: Int, velocity: Double) {
        animator.flash(row: row, column: column, velocity: velocity)
    }

    func layer(in rect: CGRect) -> FieldLayer {
        FieldLayer(
            grid: grid,
            animator: animator,
            rect: rect,
            playhead: playhead,
            detail: detail,
            alpha: alpha,
            style: style
        )
    }
}

struct FieldView: UIViewRepresentable {
    /// Called once per frame, on the main thread, with the view's bounds and
    /// how long since the last one.
    let frame: @MainActor (CGRect, Double) -> FieldFrame
    /// A field under a screen that covers it barely needs drawing — but
    /// not never. That screen can be dragged away with a finger at any
    /// moment, and a field that had stopped would be found holding whatever
    /// frame it stopped on. A few a second keep it close to true for a
    /// fraction of the cost.
    var isResting = false
    /// Where a finger is, for as long as it is down. Nil for a field that
    /// is only looked at.
    var onTouch: (@MainActor (CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.onTouch = onTouch
        if onTouch != nil {
            // UIKit rather than a SwiftUI drag, because of what it has to
            // stand in front of. A track is a screen the system zoomed open,
            // and the system's way of shutting it is a drag — the same drag
            // that draws a line down the field. A recognizer down here can
            // say that every other one has to wait for it to fail, and one
            // that never fails while a finger is on the field keeps the
            // screen where it is. The header and footer still let it go.
            let press = UILongPressGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
            press.minimumPressDuration = 0
            press.allowableMovement = .greatestFiniteMagnitude
            press.delegate = context.coordinator
            view.addGestureRecognizer(press)
        }
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        // The ground the heat sits on. With the mixer shut this is the same
        // black the bars carry, so the screen reads as one surface; opening
        // the mixer lifts the bars onto a lighter shade but the field keeps
        // its own ground — the picture stays the black it plays on. Which
        // ground that is comes down the environment and can be turned over
        // while the field is running.
        ground(context.environment.sequencerPalette, on: view)
        view.isOpaque = true
        view.framebufferOnly = true
        // The field is never still, so it draws continuously rather than
        // waiting to be invalidated.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = Self.rate(resting: isResting)

        if let device = view.device, let renderer = FieldRenderer(device: device) {
            context.coordinator.renderer = renderer
            #if DEBUG
                FieldRenderer.onScreen = renderer
            #endif
            renderer.frameProvider = { [weak view] dt in
                guard let view else { return FieldFrame() }
                return frame(CGRect(origin: .zero, size: view.bounds.size), dt)
            }
            view.delegate = renderer
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        ground(context.environment.sequencerPalette, on: view)
        let rate = Self.rate(resting: isResting)
        if view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
        context.coordinator.onTouch = onTouch
        // `frame` is a fresh closure on every SwiftUI update; the renderer
        // has to hold the current one or it would read stale state.
        context.coordinator.renderer?.frameProvider = { [weak view] dt in
            guard let view else { return FieldFrame() }
            return frame(CGRect(origin: .zero, size: view.bounds.size), dt)
        }
    }

    private static func rate(resting: Bool) -> Int {
        resting ? 15 : 120
    }

    /// Metal clears to it, UIKit paints behind it — both, or a resize shows
    /// the old ground for a frame in the strip that has not been drawn yet.
    private func ground(_ palette: SequencerPalette, on view: MTKView) {
        view.clearColor = palette.clearColor
        view.backgroundColor = UIColor(palette.fieldBackground)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: FieldRenderer?
        var onTouch: (@MainActor (CGPoint) -> Void)?

        @objc func pressed(_ press: UILongPressGestureRecognizer) {
            switch press.state {
            case .began, .changed:
                onTouch?(press.location(in: press.view))
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
