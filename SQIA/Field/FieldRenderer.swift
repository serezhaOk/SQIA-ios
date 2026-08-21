// The bridge from the field's draw list to the GPU.
//
// SQIACore decides what to draw — where every dot sits on the dome, how big,
// what colour, how bright — and this turns that list into instances and
// hands it to Metal. It makes no visual decisions of its own, which is why
// the field can be tested without a device.

import Metal
import MetalKit
import SQIACore
import simd

/// One field on screen. The sequencer draws a single layer full-screen; the
/// mixer draws one per track, in their panels.
struct FieldLayer {
    var grid: NoteGrid
    var animator: FieldAnimator
    var rect: CGRect
    /// Which row is sounding, or −1 when nothing is.
    var playhead: Int = -1
    var detail: Double = 1
    var alpha: Double = 1
}

/// A slot's hairline border, which fades in as the mixer opens. It stays put
/// while the active track flies into it.
struct FieldOutline {
    var rect: CGRect
    var alpha: Double
}

/// Everything one frame draws. The outlines are not part of any layer: they
/// belong to the slots, and the track on its way into a slot is somewhere
/// else while it travels.
struct FieldFrame {
    var layers: [FieldLayer] = []
    var outlines: [FieldOutline] = []
}

/// Matches `FieldInstance` in FieldShaders.metal. The colour comes first so
/// its sixteen-byte alignment sets the layout for both sides.
private struct FieldInstance {
    var color: SIMD4<Float>
    var center: SIMD2<Float>
    var halfSize: SIMD2<Float>
    var axis: SIMD2<Float>
    var kind: UInt32
    var padding: UInt32 = 0
}

final class FieldRenderer: NSObject, MTKViewDelegate {
    /// Dots, halos and streaks for two tracks, with room to spare. A field
    /// that wanted more than this would be drawing dots too small to see.
    private static let maxInstances = 2048
    /// Frames the CPU may run ahead of the GPU. Three is the usual number:
    /// enough that neither waits, few enough that input stays close.
    private static let maxFramesInFlight = 3

    /// Asked for the frame, on the main thread, once per frame, with how
    /// long since the last one. A closure rather than stored state so the
    /// renderer never has to be told about a change — it simply reads what
    /// is current. The frame time goes with it because the view transition
    /// has to advance on the same clock the field does, or the two drift
    /// apart over the third of a second they share.
    var frameProvider: (@MainActor (Double) -> FieldFrame)?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var instanceBuffers: [MTLBuffer] = []
    private let inFlight = DispatchSemaphore(value: maxFramesInFlight)
    private var bufferIndex = 0

    /// Scratch, reused every frame so the render loop allocates nothing.
    private var draws: [FieldDraw] = []
    private var instances: [FieldInstance] = []

    private var lastFrameTime: CFTimeInterval = 0

    /// Main-thread milliseconds the last frames took to build and encode,
    /// held at their peak the way the renderer's load is. The audio thread
    /// shares this core, so a frame that overruns is a frame that can push a
    /// buffer past its deadline.
    private(set) var frameCost: Double = 0
    /// Frames actually delivered per second, which is not what the view was
    /// asked for when the main thread cannot keep up.
    private(set) var framesPerSecond: Double = 0
    private var framesThisSecond = 0
    private var secondStarted: CFTimeInterval = 0

    #if DEBUG
        /// The renderer currently on screen, so the debug readout can ask it
        /// what a frame costs without the model having to own it. Debug
        /// scaffolding for the crackle hunt; it goes when the readout does.
        @MainActor static weak var onScreen: FieldRenderer?
    #endif

    init?(device: MTLDevice) {
        guard
            let queue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFunction = library.makeFunction(name: "fieldVertex"),
            let fragmentFunction = library.makeFunction(name: "fieldFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // `lighter`: the source, scaled by its own alpha, added to what is
        // already there. Overlapping halos build up instead of covering.
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .sourceAlpha
        attachment?.destinationAlphaBlendFactor = .one

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.device = device
        commandQueue = queue
        pipeline = state
        super.init()

        let length = MemoryLayout<FieldInstance>.stride * Self.maxInstances
        for _ in 0..<Self.maxFramesInFlight {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
            else { return nil }
            instanceBuffers.append(buffer)
        }
        instances.reserveCapacity(Self.maxInstances)
        draws.reserveCapacity(Self.maxInstances)
    }

    // ------------------------------------------------------------ MTKView --

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        // The web clamps its frame time the same way: a long stall must not
        // teleport the animation, it should just skip.
        let dt = lastFrameTime > 0 ? min(0.05, now - lastFrameTime) : 1.0 / 60.0
        lastFrameTime = now

        build(dt: dt)

        inFlight.wait()
        bufferIndex = (bufferIndex + 1) % Self.maxFramesInFlight
        let buffer = instanceBuffers[bufferIndex]
        let count = min(instances.count, Self.maxInstances)
        if count > 0 {
            instances.withUnsafeBytes { source in
                buffer.contents().copyMemory(
                    from: source.baseAddress!,
                    byteCount: count * MemoryLayout<FieldInstance>.stride)
            }
        }

        // The drawable is taken here rather than at the top of the frame:
        // asking for one blocks until the GPU frees it, and blocking before
        // the CPU work rather than after it holds the main thread for the
        // whole frame instead of the tail of it.
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commands = commandQueue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            inFlight.signal()
            return
        }

        if count > 0 {
            var viewport = SIMD2<Float>(
                Float(view.drawableSize.width / view.contentScaleFactor),
                Float(view.drawableSize.height / view.contentScaleFactor))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()

        commands.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        commands.present(drawable)
        commands.commit()

        measure(frameStarted: now)
    }

    /// What this frame cost the main thread, and how many are getting
    /// through. Both decay so a spike stays readable for a moment.
    private func measure(frameStarted: CFTimeInterval) {
        let spent = (CACurrentMediaTime() - frameStarted) * 1000
        frameCost = max(spent, frameCost * 0.97)

        framesThisSecond += 1
        if secondStarted == 0 { secondStarted = frameStarted }
        let elapsed = frameStarted - secondStarted
        if elapsed >= 1 {
            framesPerSecond = Double(framesThisSecond) / elapsed
            framesThisSecond = 0
            secondStarted = frameStarted
        }
    }

    // ------------------------------------------------------------ building --

    private func build(dt: Double) {
        instances.removeAll(keepingCapacity: true)

        // MTKView drives its delegate from the main run loop, so this is the
        // main thread; saying so lets the provider read main-actor state
        // without a hop the frame cannot afford. The whole build happens
        // inside, so nothing has to cross the boundary on the way out.
        MainActor.assumeIsolated {
            guard let frame = frameProvider?(dt) else { return }

            // Outlines first, so a panel's border sits under its dots the
            // way a stroke drawn before them does.
            for outline in frame.outlines where outline.alpha > 0.004 {
                instances.append(instance(for: outline))
            }

            for layer in frame.layers {
                layer.animator.advance(by: dt)
                let layout = Field.layout(
                    x: Double(layer.rect.minX),
                    y: Double(layer.rect.minY),
                    width: Double(layer.rect.width),
                    height: Double(layer.rect.height))

                layer.animator.draws(
                    grid: layer.grid,
                    layout: layout,
                    playhead: layer.playhead,
                    detail: layer.detail,
                    alpha: layer.alpha,
                    into: &draws)

                for draw in draws where instances.count < Self.maxInstances {
                    instances.append(instance(for: draw))
                }
            }
        }
    }

    private func instance(for outline: FieldOutline) -> FieldInstance {
        FieldInstance(
            color: SIMD4(1, 1, 1, Float(outline.alpha)),
            center: SIMD2(Float(outline.rect.midX), Float(outline.rect.midY)),
            halfSize: SIMD2(Float(outline.rect.width / 2), Float(outline.rect.height / 2)),
            axis: SIMD2(1, 0),
            kind: 3)
    }

    private func instance(for draw: FieldDraw) -> FieldInstance {
        // The web's colours are 0…255 and its halo quantisation can round
        // white up to 256, which a canvas clamps back down.
        let color = SIMD4<Float>(
            Float(min(255, draw.color.red) / 255),
            Float(min(255, draw.color.green) / 255),
            Float(min(255, draw.color.blue) / 255),
            Float(draw.alpha))

        switch draw.kind {
        case .dot:
            return FieldInstance(
                color: color,
                center: SIMD2(Float(draw.x), Float(draw.y)),
                halfSize: SIMD2(Float(draw.size), Float(draw.size)),
                axis: SIMD2(1, 0),
                kind: 0)

        case .glow:
            // The draw list places a halo by its corner, as the web places
            // its sprite; instances are placed by their middle.
            let half = Float(draw.size / 2)
            return FieldInstance(
                color: color,
                center: SIMD2(Float(draw.x) + half, Float(draw.y) + half),
                halfSize: SIMD2(half, half),
                axis: SIMD2(1, 0),
                kind: 1)

        case .streak:
            let dx = draw.x1 - draw.x
            let dy = draw.y1 - draw.y
            let length = (dx * dx + dy * dy).squareRoot()
            let axis =
                length > 1e-6
                ? SIMD2(Float(dx / length), Float(dy / length)) : SIMD2<Float>(1, 0)
            let halfWidth = Float(draw.size / 2)
            // Widened by the cap radius at each end, so the round caps have
            // somewhere to be drawn.
            return FieldInstance(
                color: color,
                center: SIMD2(Float((draw.x + draw.x1) / 2), Float((draw.y + draw.y1) / 2)),
                halfSize: SIMD2(Float(length / 2) + halfWidth, halfWidth),
                axis: axis,
                kind: 2)
        }
    }
}
