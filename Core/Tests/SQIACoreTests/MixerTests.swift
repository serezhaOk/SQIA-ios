// The renderer and the queue that feeds it.
//
// The queue test runs a real producer thread against a real consumer thread,
// which is the only way to find out whether the memory ordering is right.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

@Suite("Audio event queue")
struct AudioEventQueueTests {
    private func note(_ frame: Int64, frequency: Double = 440) -> AudioEvent {
        var recipe = VoiceRecipe()
        recipe.frequency = frequency
        return AudioEvent.note(recipe, at: frame)
    }

    @Test("Events come back in the order they went in")
    func fifo() {
        let queue = AudioEventQueue(capacity: 8)
        for i in 0..<5 { #expect(queue.push(note(Int64(i)))) }
        #expect(queue.count == 5)
        for i in 0..<5 { #expect(queue.pop()?.frame == Int64(i)) }
        #expect(queue.pop() == nil)
        #expect(queue.isEmpty)
    }

    @Test("Capacity rounds up to a power of two")
    func capacityRounding() {
        #expect(AudioEventQueue(capacity: 5).capacity == 8)
        #expect(AudioEventQueue(capacity: 256).capacity == 256)
        #expect(AudioEventQueue(capacity: 1).capacity == 2)
    }

    @Test("A full queue refuses the write rather than blocking")
    func fullQueue() {
        let queue = AudioEventQueue(capacity: 4)
        for i in 0..<4 { #expect(queue.push(note(Int64(i)))) }
        #expect(!queue.push(note(99)))
        #expect(queue.pop()?.frame == 0)
        #expect(queue.push(note(99)))
    }

    @Test("Indices wrap without losing anything")
    func wraps() {
        let queue = AudioEventQueue(capacity: 4)
        for round in 0..<1000 {
            #expect(queue.push(note(Int64(round))))
            #expect(queue.pop()?.frame == Int64(round))
        }
    }

    @Test("Peeking does not consume")
    func peeking() {
        let queue = AudioEventQueue(capacity: 4)
        queue.push(note(7))
        #expect(queue.peek()?.frame == 7)
        #expect(queue.peek()?.frame == 7)
        #expect(queue.pop()?.frame == 7)
        #expect(queue.peek() == nil)
    }

    /// Carries the consumer thread's verdict back out. The consumer writes
    /// it before signalling and the test reads it after waiting, so the
    /// semaphore is what orders the two.
    private final class Verdict: @unchecked Sendable {
        var mismatch: String?
    }

    /// The point of the whole exercise: one thread writing while another
    /// reads, with nothing lost, reordered or torn.
    @Test("A producer thread and a consumer thread agree", .timeLimit(.minutes(1)))
    func acrossThreads() {
        let queue = AudioEventQueue(capacity: 64)
        let total = 200_000
        let verdict = Verdict()
        let done = DispatchSemaphore(value: 0)

        let consumer = Thread {
            var next: Int64 = 0
            while next < Int64(total) {
                guard let event = queue.pop() else { continue }
                // Order and payload both have to survive the crossing.
                if event.frame != next || event.recipe.frequency != Double(next % 97) {
                    verdict.mismatch =
                        "at \(next): frame \(event.frame), freq \(event.recipe.frequency)"
                    break
                }
                next += 1
            }
            done.signal()
        }
        consumer.start()

        for i in 0..<total {
            var recipe = VoiceRecipe()
            recipe.frequency = Double(Int64(i) % 97)
            while !queue.push(AudioEvent.note(recipe, at: Int64(i))) { /* full */  }
        }

        #expect(done.wait(timeout: .now() + 30) == .success)
        #expect(verdict.mismatch == nil, "\(verdict.mismatch ?? "")")
    }
}

@Suite("Audio mixer")
struct AudioMixerTests {
    private func render(_ mixer: AudioMixer, frames: Int) -> [Double] {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                mixer.render(frameCount: frames, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        return left.map(Double.init)
    }

    private func onset(_ output: [Double], threshold: Double = 1e-4) -> Int? {
        output.firstIndex { abs($0) > threshold }
    }

    /// A long, plain note: loud enough to find, and with nothing rolled so a
    /// test reads the same every run.
    private func steadyNote(frequency: Double = 220) -> VoiceRecipe {
        var recipe = VoiceRecipe()
        recipe.preset = .reverie
        recipe.source = .oscillator
        recipe.waveform = .sine
        recipe.frequency = frequency
        recipe.gain = 1
        recipe.attack = 0.001
        recipe.decay = 0.01
        recipe.sustain = 1
        recipe.release = 0.05
        recipe.duration = 0.5
        return recipe
    }

    @Test("An idle mixer is silent")
    func idleIsSilent() {
        let mixer = AudioMixer(sampleRate: rate)
        #expect(render(mixer, frames: 2048).allSatisfy { $0 == 0 })
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test("A scheduled note sounds")
    func playsANote() {
        let mixer = AudioMixer(sampleRate: rate)
        mixer.schedule(AudioEvent.note(steadyNote(), at: 100))

        let output = render(mixer, frames: 8192)
        #expect(onset(output) != nil)
        #expect(mixer.activeVoiceCount == 1)
        #expect(mixer.droppedNotes == 0)
    }

    /// Timing is what a sequencer is for. The absolute onset carries the
    /// limiter's 6 ms lookahead and the chain's own delay, so the thing to
    /// check is that moving a note by N frames moves the sound by N frames.
    @Test("Scheduling is sample accurate")
    func sampleAccurate() {
        func onsetFor(_ frame: Int64) -> Int {
            let mixer = AudioMixer(sampleRate: rate)
            mixer.schedule(AudioEvent.note(steadyNote(), at: frame))
            return onset(render(mixer, frames: 16384)) ?? -1
        }

        let early = onsetFor(100)
        let late = onsetFor(1100)
        #expect(early > 0)
        #expect(late - early == 1000)
    }

    @Test("An event whose moment has passed still fires")
    func lateEventsStillFire() {
        let mixer = AudioMixer(sampleRate: rate)
        _ = render(mixer, frames: 4096)
        mixer.schedule(AudioEvent.note(steadyNote(), at: 10))
        _ = render(mixer, frames: 2048)
        #expect(mixer.activeVoiceCount == 1)
    }

    @Test("The voice budget drops notes rather than stealing them")
    func voiceBudget() {
        let mixer = AudioMixer(sampleRate: rate, voiceLimit: 4)
        for i in 0..<10 {
            mixer.schedule(AudioEvent.note(steadyNote(), at: Int64(i)))
        }
        _ = render(mixer, frames: 1024)

        #expect(mixer.activeVoiceCount == 4)
        #expect(mixer.droppedNotes == 6)
    }

    @Test("Voices retire when their envelope runs out")
    func voicesRetire() {
        let mixer = AudioMixer(sampleRate: rate)
        var recipe = steadyNote()
        recipe.duration = 0.05
        recipe.release = 0.05
        mixer.schedule(AudioEvent.note(recipe, at: 0))

        _ = render(mixer, frames: 1024)
        #expect(mixer.activeVoiceCount == 1)

        _ = render(mixer, frames: Int(rate))
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test("Silence stops everything at once")
    func panic() {
        let mixer = AudioMixer(sampleRate: rate)
        for i in 0..<8 {
            mixer.schedule(AudioEvent.note(steadyNote(), at: Int64(i)))
        }
        _ = render(mixer, frames: 512)
        #expect(mixer.activeVoiceCount > 0)

        mixer.panic()
        let after = render(mixer, frames: 8192)
        #expect(mixer.activeVoiceCount == 0)
        #expect(after.suffix(512).allSatisfy { $0 == 0 })
    }

    @Test("Each preset goes through its own chain")
    func presetsAreSeparate() {
        // A drift that shuts one preset's filter right down should not
        // quieten another's.
        func level(driftingOther: Bool) -> Double {
            let mixer = AudioMixer(sampleRate: rate)
            if driftingOther {
                var drift = PresetDrift()
                drift.preset = .machine
                drift.cutoff = 30
                drift.cutoffRamp = 0.001
                mixer.schedule(AudioEvent.drift(drift, at: 0))
            }
            var recipe = steadyNote()
            recipe.preset = .reverie
            recipe.duration = 0.4
            mixer.schedule(AudioEvent.note(recipe, at: 100))
            let out = render(mixer, frames: Int(rate / 4))
            return out.map(abs).max() ?? 0
        }

        let plain = level(driftingOther: false)
        #expect(abs(level(driftingOther: true) - plain) < plain * 0.01)
    }

    @Test("A drift is taken without a click or a jump")
    func driftIsSmooth() {
        let mixer = AudioMixer(sampleRate: rate)
        var recipe = steadyNote()
        recipe.duration = 2
        recipe.release = 0.5
        mixer.schedule(AudioEvent.note(recipe, at: 0))

        var drift = PresetDrift()
        drift.preset = .reverie
        drift.cutoff = 5000
        drift.cutoffRamp = 1
        drift.echo = 0.24
        drift.lead = Int(0.08 * rate)
        mixer.schedule(AudioEvent.drift(drift, at: Int64(rate / 2)))

        let out = render(mixer, frames: Int(rate * 2))
        // No sample may jump further than a full-scale swing from the last.
        for (a, b) in zip(out, out.dropFirst()) {
            #expect(abs(b - a) < 0.5, "step of \(abs(b - a))")
        }
        #expect(out.allSatisfy { $0.isFinite })
    }

    /// A full pattern is a dozen notes a second for as long as anyone plays.
    /// Nothing should creep: not the voice count, not the output level.
    @Test("A long busy run stays level and never runs out of voices")
    func sustainedLoad() {
        let mixer = AudioMixer(sampleRate: rate)
        let random = Mulberry32(seed: 99)
        let blockFrames = 512
        var peak = 0.0

        var next: Int64 = 0
        for block in 0..<Int(rate * 30) / blockFrames {
            while next < mixer.frame + Int64(blockFrames) {
                for column in 0..<6 {
                    let preset: SynthPreset = column % 2 == 0 ? .reverie : .machine
                    for voice in SynthVoicing.notes(
                        preset: preset, midi: 48 + column * 2, velocity: 0.9,
                        using: random)
                    {
                        mixer.schedule(
                            AudioEvent.note(
                                voice.recipe,
                                at: next + Int64(voice.offset * rate)))
                    }
                }
                next += Int64(rate * 0.125)
            }
            let output = render(mixer, frames: blockFrames)
            if block > 40 { peak = max(peak, output.map(abs).max() ?? 0) }
        }

        #expect(peak > 0.01, "the mixer went quiet")
        #expect(peak < 1.5, "the limiter let it run away: \(peak)")
    }
}
