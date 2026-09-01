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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
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
        view.preferredFramesPerSecond = 120

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
        // `frame` is a fresh closure on every SwiftUI update; the renderer
        // has to hold the current one or it would read stale state.
        context.coordinator.renderer?.frameProvider = { [weak view] dt in
            guard let view else { return FieldFrame() }
            return frame(CGRect(origin: .zero, size: view.bounds.size), dt)
        }
    }

    /// Metal clears to it, UIKit paints behind it — both, or a resize shows
    /// the old ground for a frame in the strip that has not been drawn yet.
    private func ground(_ palette: SequencerPalette, on view: MTKView) {
        view.clearColor = palette.clearColor
        view.backgroundColor = UIColor(palette.fieldBackground)
    }

    @MainActor
    final class Coordinator {
        var renderer: FieldRenderer?
    }
}
