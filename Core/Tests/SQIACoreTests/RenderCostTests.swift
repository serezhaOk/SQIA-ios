// What the renderer costs.
//
// The audio thread has one job and a hard deadline: fill a buffer before the
// hardware needs it. Miss it and you get a click, and enough clicks is a
// crackle. So the cost is measured here rather than discovered on a device.
//
// The number that matters is the realtime factor: seconds of CPU per second
// of audio. Anything at or above 1.0 cannot work at all, and anything above
// roughly 0.2 will glitch as soon as the phone has something else to do.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

/// Renders a busy passage and reports what it cost.
@discardableResult
private func measureRender(
    seconds: Double,
    voicesPerStep: Int,
    presets: [SynthPreset],
    label: String
) -> Double {
    let mixer = AudioMixer(sampleRate: rate)
    let random = Mulberry32(seed: 1234)
    let blockFrames = 512
    let blocks = Int(seconds * rate) / blockFrames

    var left = [Float](repeating: 0, count: blockFrames)
    var right = [Float](repeating: 0, count: blockFrames)

    // Fill the queue as the transport would: a step every eighth of a second.
    var next: Int64 = 0
    var scheduled = 0

    let started = DispatchTime.now()
    for _ in 0..<blocks {
        while next < mixer.frame + Int64(blockFrames) {
            for i in 0..<voicesPerStep {
                let preset = presets[i % presets.count]
                for voice in SynthVoicing.notes(
                    preset: preset, midi: 48 + (i * 3) % 12, velocity: 0.9, using: random)
                {
                    if mixer.schedule(
                        AudioEvent.note(
                            voice.recipe, at: next + Int64(voice.offset * rate)))
                    {
                        scheduled += 1
                    }
                }
            }
            next += Int64(rate * 0.125)
        }

        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                mixer.render(
                    frameCount: blockFrames, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds)
        / 1_000_000_000

    let audio = Double(blocks * blockFrames) / rate
    let factor = elapsed / audio
    print(
        String(
            format: "  %@: %.3f× realtime (%d notes, %.1fs of audio in %.2fs)",
            label, factor, scheduled, audio, elapsed))
    return factor
}

@Suite("Render cost")
struct RenderCostTests {
    /// Release is the bar that means something: the app ships optimised, and
    /// this is where there has to be room left for the rest of the phone.
    ///
    /// Debug is now close behind it — the package compiles at `-O` in either
    /// configuration, because a Run build is what plays on the device — but
    /// it is held only loosely. A shared CI runner is not the machine anyone
    /// ships on, and this number should catch a collapse, not drift.
    #if DEBUG
        static let ceiling = 1.0
    #else
        static let ceiling = 0.25
    #endif

    @Test("An idle mixer costs almost nothing")
    func idle() {
        let factor = measureRender(
            seconds: 5, voicesPerStep: 0, presets: [.reverie], label: "idle")
        #expect(factor < Self.ceiling / 2, "idle cost \(factor)× realtime")
    }

    @Test("One track with a few voices is cheap")
    func light() {
        let factor = measureRender(
            seconds: 5, voicesPerStep: 3, presets: [.reverie], label: "light")
        #expect(factor < Self.ceiling, "light cost \(factor)× realtime")
    }

    @Test("Two tracks with a full pattern still fits")
    func heavy() {
        let factor = measureRender(
            seconds: 5, voicesPerStep: 12, presets: [.reverie, .machine], label: "heavy")
        #expect(factor < Self.ceiling, "heavy cost \(factor)× realtime")
    }
}
