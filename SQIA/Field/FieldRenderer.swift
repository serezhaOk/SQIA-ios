// The bridge from the field's draw list to the GPU.
//
// SQIACore decides what to draw — where every dot sits, how big, what colour,
// how bright — and this turns that list into instances and hands it to Metal.
// It makes no visual decisions of its own, which is why the field can be
// tested without a device.
//
// The heat field needs one thing the dot field never did: a pass of its own.
// Sources have to be summed before anything can be coloured, because the
// colour of a pixel depends on the total there and not on any one source. So
// they are added up into an off-screen texture and a full-screen pass reads
// that back. Half resolution — it is all soft gradients, and the upsample
// smooths them rather than costing anything.

import Foundation
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
    /// Dome or flat, dots or heat. Hit-testing has to be given the same one,
    /// or a finger lands in the wrong cell.
    var style: FieldStyle = .heat
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
    /// Source only: how hot the flash under it still is.
    var energy: Float = 0
    var padding: UInt32 = 0
}

/// Matches `HeatUniforms` in FieldShaders.metal.
///
/// None of these is a fact and none can be judged anywhere but on a screen,
/// so they are not written down here at all: they come off the `FieldTuning`
/// riding on the layer, which is what the panel edits.
private struct HeatUniforms {
    var time: Float = 0
    /// How far the sum is stretched across the ramp. A single brush stroke
    /// sums to about 1.3 at its middle and a crowded corner to three or
    /// four, so this is what decides that one note is cool and a cluster
    /// burns.
    var gain: Float = 0.26
    /// Below this the field dissolves into the ground.
    var edge: Float = 0.12
    var rippleFrequency: Float = 4.5
    var rippleSpeed: Float = 1.6
    var rippleAmplitude: Float = 0.16
    /// Above zero the ramp is quantised into this many bands — the stepped
    /// contour look. Off; the reference that settled the palette is smooth.
    var bands: Float = 0
    var padding: Float = 0

    mutating func take(_ tuning: FieldTuning) {
        gain = Float(tuning.gain)
        edge = Float(tuning.edge)
        rippleFrequency = Float(tuning.rippleFrequency)
        rippleSpeed = Float(tuning.rippleSpeed)
        rippleAmplitude = Float(tuning.rippleAmplitude)
    }
}

/// The two ramps, flattened for the shader: rgb in xyz and the stop's place
/// along the ramp in w, rest first and heat after it.
private func rampStops(_ tuning: FieldTuning) -> [SIMD4<Float>] {
    func packed(_ stops: [ColorStop], count: Int) -> [SIMD4<Float>] {
        // The shader walks a fixed count. A panel mid-edit must not be able
        // to hand it a short buffer.
        let usable = stops.prefix(count)
        var out = usable.map {
            SIMD4<Float>(
                Float($0.color.red / 255), Float($0.color.green / 255),
                Float($0.color.blue / 255), Float($0.at))
        }
        while out.count < count { out.append(out.last ?? SIMD4<Float>(1, 1, 1, 1)) }
        return out
    }
    return packed(tuning.rest, count: FieldTuning.restStops)
        + packed(tuning.heat, count: FieldTuning.heatStops)
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

    /// The accumulator is kept at half the drawable, which costs a quarter
    /// of the fill and blurs the sum slightly on the way back up — both of
    /// which the picture wants.
    private static let accumulationScale = 0.5

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Sums sources into the accumulator; adds, and never blends.
    private let sourcePipeline: MTLRenderPipelineState
    /// Reads the sum back and maps it through the ramp.
    private let heatPipeline: MTLRenderPipelineState
    private var accumulation: MTLTexture?
    private var uniforms = HeatUniforms()
    private var stops = rampStops(.current)
    private var tuning = FieldTuning.current
    private var elapsed: Double = 0
    private var instanceBuffers: [MTLBuffer] = []
    private let inFlight = DispatchSemaphore(value: maxFramesInFlight)
    private var bufferIndex = 0

    /// Scratch, reused every frame so the render loop allocates nothing.
    private var draws: [FieldDraw] = []
    private var instances: [FieldInstance] = []
    /// The sources, held apart because they are drawn into somewhere else.
    private var sources: [FieldInstance] = []

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
        /// The renderer currently on screen, so anything that wants to know
        /// what a frame costs can ask it without the model having to own it.
        ///
        /// Nothing reads this at the moment: the meter that used to float
        /// over the field is gone, because it sat on top of the picture being
        /// worked on. The measuring stays — it is the instrument for the next
        /// time something crackles, and a readout is a small view away.
        @MainActor static weak var onScreen: FieldRenderer?
    #endif

    init?(device: MTLDevice) {
        guard
            let queue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFunction = library.makeFunction(name: "fieldVertex"),
            let fragmentFunction = library.makeFunction(name: "fieldFragment"),
            let sourceVertex = library.makeFunction(name: "sourceVertex"),
            let sourceFragment = library.makeFunction(name: "sourceFragment"),
            let heatVertex = library.makeFunction(name: "heatVertex"),
            let heatFragment = library.makeFunction(name: "heatFragment")
        else { return nil }

        // Source over rather than the web's `lighter`. The heat pass below
        // already decides a pixel's colour from the whole sum, so adding
        // its result to whatever the resting grid left there would only
        // wash the ramp out at the exact places the sum is highest.
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .sourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        // The full-screen pass that colours the sum. Same blending: it lies
        // over the ground and fades into it at the bottom of the ramp.
        descriptor.vertexFunction = heatVertex
        descriptor.fragmentFunction = heatFragment
        guard let heatState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        // The accumulator. Two channels, floating point because the sum runs
        // past one wherever notes crowd together — and running past one is
        // the whole signal, not an overflow to be clamped away.
        descriptor.vertexFunction = sourceVertex
        descriptor.fragmentFunction = sourceFragment
        attachment?.pixelFormat = .rg16Float
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .one
        guard let sourceState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.device = device
        commandQueue = queue
        pipeline = state
        sourcePipeline = sourceState
        heatPipeline = heatState
        super.init()

        let length = MemoryLayout<FieldInstance>.stride * Self.maxInstances
        for _ in 0..<Self.maxFramesInFlight {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
            else { return nil }
            instanceBuffers.append(buffer)
        }
        instances.reserveCapacity(Self.maxInstances)
        // Two fields are on screen at once while the mixer opens, and every
        // drawn note in each of them is a source.
        sources.reserveCapacity(NoteGrid.count * 2)
        draws.reserveCapacity(Self.maxInstances)
    }

    // ------------------------------------------------------------ MTKView --

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resizeAccumulation(for: size)
    }

    private func resizeAccumulation(for size: CGSize) {
        let width = max(1, Int(size.width * Self.accumulationScale))
        let height = max(1, Int(size.height * Self.accumulationScale))
        if let accumulation, accumulation.width == width, accumulation.height == height {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        accumulation = device.makeTexture(descriptor: descriptor)
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        // The web clamps its frame time the same way: a long stall must not
        // teleport the animation, it should just skip.
        let dt = lastFrameTime > 0 ? min(0.05, now - lastFrameTime) : 1.0 / 60.0
        lastFrameTime = now

        build(dt: dt)

        elapsed += dt
        uniforms.time = Float(elapsed)

        inFlight.wait()
        bufferIndex = (bufferIndex + 1) % Self.maxFramesInFlight
        let buffer = instanceBuffers[bufferIndex]
        let stride = MemoryLayout<FieldInstance>.stride
        // One buffer, the drawn primitives first and the sources after them,
        // so the accumulation pass is the same buffer read from an offset.
        let count = min(instances.count, Self.maxInstances)
        let sourceCount = min(sources.count, Self.maxInstances - count)
        if count > 0 {
            instances.withUnsafeBytes { source in
                buffer.contents().copyMemory(
                    from: source.baseAddress!, byteCount: count * stride)
            }
        }
        if sourceCount > 0 {
            sources.withUnsafeBytes { source in
                buffer.contents().advanced(by: count * stride).copyMemory(
                    from: source.baseAddress!, byteCount: sourceCount * stride)
            }
        }

        // The drawable is taken here rather than at the top of the frame:
        // asking for one blocks until the GPU frees it, and blocking before
        // the CPU work rather than after it holds the main thread for the
        // whole frame instead of the tail of it.
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commands = commandQueue.makeCommandBuffer()
        else {
            inFlight.signal()
            return
        }

        var viewport = SIMD2<Float>(
            Float(view.drawableSize.width / view.contentScaleFactor),
            Float(view.drawableSize.height / view.contentScaleFactor))

        // First pass: add the sources up. Nothing is decided about colour
        // here — this only works out how much field there is at each point,
        // which is what lets two notes come out as one shape.
        resizeAccumulation(for: view.drawableSize)
        let summed = sourceCount > 0 ? accumulation : nil
        if let summed {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = summed
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store

            if let accumulate = commands.makeRenderCommandEncoder(descriptor: pass) {
                accumulate.setRenderPipelineState(sourcePipeline)
                accumulate.setVertexBuffer(buffer, offset: count * stride, index: 0)
                accumulate.setVertexBytes(
                    &viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
                accumulate.drawPrimitives(
                    type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                    instanceCount: sourceCount)
                accumulate.endEncoding()
            }
        }

        guard let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor) else {
            inFlight.signal()
            return
        }

        // Second pass: read the sum back and colour it. Under the drawn
        // primitives, so the resting grid and the slot outlines stay legible
        // over a blob rather than beneath it.
        if let summed {
            encoder.setRenderPipelineState(heatPipeline)
            encoder.setFragmentTexture(summed, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<HeatUniforms>.stride, index: 0)
            encoder.setFragmentBytes(
                stops, length: MemoryLayout<SIMD4<Float>>.stride * stops.count, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        if count > 0 {
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
        sources.removeAll(keepingCapacity: true)

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
                    height: Double(layer.rect.height),
                    style: layer.style)

                // Whatever the panel is holding. Every layer on screen is
                // the same field, so the last one wins and they agree.
                if layer.style.tuning != tuning {
                    tuning = layer.style.tuning
                    uniforms.take(tuning)
                    stops = rampStops(tuning)
                }

                layer.animator.draws(
                    grid: layer.grid,
                    layout: layout,
                    playhead: layer.playhead,
                    detail: layer.detail,
                    alpha: layer.alpha,
                    into: &draws)

                for draw in draws {
                    if draw.kind == .source {
                        sources.append(instance(for: draw))
                    } else if instances.count < Self.maxInstances {
                        instances.append(instance(for: draw))
                    }
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

        case .source:
            // A square big enough to hold the falloff; the fragment shader
            // throws away everything outside the circle inside it.
            return FieldInstance(
                color: SIMD4(0, 0, 0, Float(draw.alpha)),
                center: SIMD2(Float(draw.x), Float(draw.y)),
                halfSize: SIMD2(Float(draw.size), Float(draw.size)),
                axis: SIMD2(1, 0),
                kind: 4,
                energy: Float(draw.energy))

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
