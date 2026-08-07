// The field, on screen.
//
// An MTKView driving `FieldRenderer` at the display's own rate. The field
// animates every frame whether or not anything changed — it breathes, and
// blooms decay — so there is no point asking SwiftUI to redraw it.

import MetalKit
import SQIACore
import SwiftUI

/// The state one field draws from. A class so the renderer can read the
/// current values each frame without SwiftUI having to push them.
@MainActor
final class FieldScene {
    var grid = NoteGrid()
    /// Row currently sounding, or −1.
    var playhead = -1
    var detail: Double = 1
    var alpha: Double = 1
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
            alpha: alpha
        )
    }
}

struct FieldView: UIViewRepresentable {
    /// Called once per frame, on the main thread, with the view's bounds.
    let layers: (CGRect) -> [FieldLayer]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isOpaque = true
        view.backgroundColor = .black
        view.framebufferOnly = true
        // The field is never still, so it draws continuously rather than
        // waiting to be invalidated.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 120

        if let device = view.device, let renderer = FieldRenderer(device: device) {
            context.coordinator.renderer = renderer
            renderer.layerProvider = { [weak view] in
                guard let view else { return [] }
                return layers(CGRect(origin: .zero, size: view.bounds.size))
            }
            view.delegate = renderer
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        // `layers` is a fresh closure on every SwiftUI update; the renderer
        // has to hold the current one or it would read stale state.
        context.coordinator.renderer?.layerProvider = { [weak view] in
            guard let view else { return [] }
            return layers(CGRect(origin: .zero, size: view.bounds.size))
        }
    }

    @MainActor
    final class Coordinator {
        var renderer: FieldRenderer?
    }
}
