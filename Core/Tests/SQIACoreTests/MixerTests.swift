// The renderer and the queue that feeds it.
//
// The queue test runs a real producer thread against a real consumer thread,
// which is the only way to find out whether the memory ordering is right.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

/// A decoded sample backed by storage that outlives the test's use of it —
/// the same arrangement the app makes, where samples are loaded once and
/// never freed so the render thread never touches a reference count.
private final class TestSample {
    let storage: UnsafeMutableBufferPointer<Float>
    let ref: SampleRef

    /// Mono storage exposed as a mono `SampleRef` — the right channel is
    /// nil, which the voice reads as "heard on both sides".
    init(frames: [Float], sampleRate: Double = rate) {
        storage = .allocate(capacity: frames.count)
        _ = storage.initialize(from: frames)
        ref = SampleRef(
            left: UnsafePointer(storage.baseAddress!),
            right: nil,
            frameCount: frames.count,
            sampleRate: sampleRate
        )
    }

    /// A steady tone, loud enough to see through an envelope.
    static func tone(seconds: Double, frequency: Double = 220) -> TestSample {
        let count = Int(seconds * rate)
        return TestSample(
            frames: (0..<count).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) })
    }

    deinit {
        storage.deallocate()
    }
}

@Suite("Audio event queue")
struct AudioEventQueueTests {
    private func hit(_ frame: Int64) -> AudioEvent {
        AudioEvent(kind: .sampleHit, frame: frame)
    }

    @Test("Events come back in the order they went in")
    func fifo() {
        let queue = AudioEventQueue(capacity: 8)
        for i in 0..<5 { #expect(queue.push(hit(Int64(i)))) }
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
        for i in 0..<4 { #expect(queue.push(hit(Int64(i)))) }
        #expect(!queue.push(hit(99)))
        // Making room lets the next one in.
        #expect(queue.pop()?.frame == 0)
        #expect(queue.push(hit(99)))
    }

    @Test("Indices wrap without losing anything")
    func wraps() {
        let queue = AudioEventQueue(capacity: 4)
        for round in 0..<1000 {
            #expect(queue.push(hit(Int64(round))))
            #expect(queue.pop()?.frame == Int64(round))
        }
    }

    @Test("Peeking does not consume")
    func peeking() {
        let queue = AudioEventQueue(capacity: 4)
        queue.push(hit(7))
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
                if event.frame != next || event.velocity != Double(next % 97) {
                    verdict.mismatch =
                        "at \(next): got frame \(event.frame), velocity \(event.velocity)"
                    break
                }
                next += 1
            }
            done.signal()
        }
        consumer.start()

        for i in 0..<total {
            let event = AudioEvent(
                kind: .sampleHit, frame: Int64(i), velocity: Double(Int64(i) % 97))
            while !queue.push(event) { /* full: let the consumer catch up */  }
        }

        #expect(done.wait(timeout: .now() + 30) == .success)
        #expect(verdict.mismatch == nil, "\(verdict.mismatch ?? "")")
    }
}

@Suite("Sample voice")
struct SampleVoiceTests {
    /// A ramp read back at a fractional rate: every output should land on
    /// the straight line between neighbouring frames, which is what says the
    /// interpolation is doing its job rather than merely stepping.
    @Test("Between frames it interpolates")
    func interpolates() {
        let count = 1000
        let sample = TestSample(frames: (0..<count).map { Float($0) })
        var voice = SampleVoice()
        // A long tail, so the envelope is flat enough to divide back out.
        voice.start(
            sample: sample.ref, rate: 0.5, velocity: 1, releaseScale: 0.9, sampleRate: rate)

        let envelope = SampleEnvelope(
            peak: 1,
            release: SampleEnvelope.release(
                bufferDuration: sample.ref.duration, rate: 0.5, scale: 0.9))

        // The nth call reads position (n−1)·0.5 and is scaled by the
        // envelope at that age — so on a ramp the output says exactly where
        // in the buffer the voice is, including between frames.
        for age in 0..<100 {
            let out = voice.render()
            let expected = Double(age) * 0.5 * envelope.value(at: Double(age) / rate)
            #expect(abs(out.left - expected) < 1e-9, "age \(age): \(out.left) vs \(expected)")
            #expect(out.right == out.left, "mono source should reach both sides")
        }
    }

    @Test("It stops at the end of the buffer")
    func stopsAtTheEnd() {
        let sample = TestSample(frames: [Float](repeating: 1, count: 100))
        var voice = SampleVoice()
        voice.start(
            sample: sample.ref, rate: 1, velocity: 1, releaseScale: 0.9, sampleRate: rate)
        for _ in 0..<100 {
            _ = voice.render()
            #expect(voice.isActive)
        }
        // Running off the end is noticed on the call that would have read
        // past it.
        #expect(voice.render() == (0, 0))
        #expect(!voice.isActive)
    }

    @Test("A file recorded at another rate is corrected for")
    func sampleRateCorrection() {
        // 24 kHz material into a 48 kHz engine advances half a frame per
        // output frame, or it would play an octave high.
        let sample = TestSample(
            frames: (0..<1000).map { Float($0) }, sampleRate: rate / 2)
        var voice = SampleVoice()
        voice.start(
            sample: sample.ref, rate: 1, velocity: 1, releaseScale: 0.9, sampleRate: rate)

        let envelope = SampleEnvelope(
            peak: 1,
            release: SampleEnvelope.release(
                bufferDuration: sample.ref.duration, rate: 1, scale: 0.9))
        for _ in 0..<40 { _ = voice.render() }
        let out = voice.render()
        #expect(abs(out.left / envelope.value(at: 40 / rate) - 20) < 1e-6)
    }

    /// Every sample in the set is stereo, so the two sides have to stay
    /// apart all the way to the output.
    @Test("A stereo source keeps its sides")
    func stereoIsPreserved() {
        let count = 500
        let leftChannel = UnsafeMutableBufferPointer<Float>.allocate(capacity: count)
        let rightChannel = UnsafeMutableBufferPointer<Float>.allocate(capacity: count)
        defer {
            leftChannel.deallocate()
            rightChannel.deallocate()
        }
        for i in 0..<count {
            leftChannel[i] = 1
            rightChannel[i] = -0.25
        }

        var voice = SampleVoice()
        voice.start(
            sample: SampleRef(
                left: UnsafePointer(leftChannel.baseAddress!),
                right: UnsafePointer(rightChannel.baseAddress!),
                frameCount: count,
                sampleRate: rate
            ),
            rate: 1, velocity: 1, releaseScale: 0.9, sampleRate: rate)

        for _ in 0..<10 { _ = voice.render() }
        let out = voice.render()
        #expect(out.left > 0)
        #expect(out.right < 0)
        #expect(abs(out.right / out.left + 0.25) < 1e-9)
    }

    @Test("Starting on an empty sample leaves the voice free")
    func emptySample() {
        var voice = SampleVoice()
        voice.start(sample: .empty, rate: 1, velocity: 1, releaseScale: 1, sampleRate: rate)
        #expect(!voice.isActive)
        #expect(voice.render() == (0, 0))
    }
}

@Suite("Audio mixer")
struct AudioMixerTests {
    private func render(_ mixer: AudioMixer, frames: Int) -> [Double] {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                mixer.render(
                    frameCount: frames, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        // Both channels carry the same signal for now; check they do.
        for i in 0..<frames { precondition(left[i] == right[i]) }
        return left.map(Double.init)
    }

    private func onset(_ output: [Double], threshold: Double = 1e-4) -> Int? {
        output.firstIndex { abs($0) > threshold }
    }

    @Test("An idle mixer is silent")
    func idleIsSilent() {
        let mixer = AudioMixer(sampleRate: rate)
        #expect(render(mixer, frames: 2048).allSatisfy { $0 == 0 })
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test("A scheduled hit sounds")
    func playsAHit() {
        let sample = TestSample.tone(seconds: 0.5)
        let mixer = AudioMixer(sampleRate: rate)
        mixer.schedule(
            AudioEvent(kind: .sampleHit, frame: 100, sample: sample.ref, velocity: 1))

        let output = render(mixer, frames: 4096)
        #expect(onset(output) != nil)
        #expect(mixer.activeVoiceCount == 1)
        #expect(mixer.droppedNotes == 0)
    }

    /// Timing is what a sequencer is for. The absolute onset carries the
    /// limiter's 6 ms lookahead, so the thing to check is that moving a note
    /// by N frames moves the sound by N frames.
    @Test("Scheduling is sample accurate")
    func sampleAccurate() {
        let sample = TestSample.tone(seconds: 0.5)

        func onsetFor(_ frame: Int64) -> Int {
            let mixer = AudioMixer(sampleRate: rate)
            mixer.schedule(
                AudioEvent(kind: .sampleHit, frame: frame, sample: sample.ref, velocity: 1))
            return onset(render(mixer, frames: 8192)) ?? -1
        }

        let early = onsetFor(100)
        let late = onsetFor(1100)
        #expect(early > 0)
        #expect(late - early == 1000)
    }

    @Test("An event whose moment has passed still fires")
    func lateEventsStillFire() {
        let sample = TestSample.tone(seconds: 0.2)
        let mixer = AudioMixer(sampleRate: rate)
        _ = render(mixer, frames: 4096)  // move the clock past the event
        mixer.schedule(
            AudioEvent(kind: .sampleHit, frame: 10, sample: sample.ref, velocity: 1))

        _ = render(mixer, frames: 2048)
        #expect(mixer.activeVoiceCount == 1)
    }

    @Test("Playback rate changes how fast the sample is read")
    func playbackRate() {
        // A ramp, so the value read back says where in the buffer we are.
        //
        // Ten seconds of it on purpose: the tail is `min(1.5, duration/rate)`
        // scaled, so a shorter sample would give the two rates different
        // envelopes and the comparison would measure both effects at once.
        // Past 1.5 s the cap bites for either rate and only the reading speed
        // differs.
        let count = Int(rate * 10)
        let sample = TestSample(frames: (0..<count).map { Float($0) / Float(count) })

        func valueAfter(rate playback: Double, frames: Int) -> Double {
            let mixer = AudioMixer(sampleRate: rate)
            mixer.schedule(
                AudioEvent(
                    kind: .sampleHit, frame: 0, sample: sample.ref, rate: playback,
                    velocity: 1, releaseScale: 0.9))
            return render(mixer, frames: frames).last ?? 0
        }

        let single = valueAfter(rate: 1, frames: 4096)
        let double = valueAfter(rate: 2, frames: 4096)
        #expect(single > 0)
        #expect(abs(double / single - 2) < 0.05, "ratio \(double / single)")
    }

    @Test("The voice budget drops notes rather than stealing them")
    func voiceBudget() {
        let sample = TestSample.tone(seconds: 2)
        let mixer = AudioMixer(sampleRate: rate, voiceLimit: 4)
        for i in 0..<10 {
            mixer.schedule(
                AudioEvent(
                    kind: .sampleHit, frame: Int64(i), sample: sample.ref, velocity: 1,
                    releaseScale: 0.9))
        }
        _ = render(mixer, frames: 1024)

        #expect(mixer.activeVoiceCount == 4)
        #expect(mixer.droppedNotes == 6)
    }

    @Test("Voices retire when their envelope runs out")
    func voicesRetire() {
        let sample = TestSample.tone(seconds: 2)
        let mixer = AudioMixer(sampleRate: rate)
        mixer.schedule(
            AudioEvent(
                kind: .sampleHit, frame: 0, sample: sample.ref, velocity: 1,
                releaseScale: 0.1))
        _ = render(mixer, frames: 1024)
        #expect(mixer.activeVoiceCount == 1)

        // The tail is 10% of 1.5 s plus the stop margin; two seconds is well
        // past it.
        _ = render(mixer, frames: Int(rate * 2))
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test("Silence stops everything at once")
    func panic() {
        let sample = TestSample.tone(seconds: 2)
        let mixer = AudioMixer(sampleRate: rate)
        for i in 0..<8 {
            mixer.schedule(
                AudioEvent(
                    kind: .sampleHit, frame: Int64(i), sample: sample.ref, velocity: 1))
        }
        _ = render(mixer, frames: 512)
        #expect(mixer.activeVoiceCount > 0)

        mixer.panic()
        let after = render(mixer, frames: 2048)
        #expect(mixer.activeVoiceCount == 0)
        #expect(after.suffix(512).allSatisfy { $0 == 0 })
    }

    @Test("A missing sample is ignored, not crashed on")
    func emptySample() {
        let mixer = AudioMixer(sampleRate: rate)
        mixer.schedule(AudioEvent(kind: .sampleHit, frame: 0, sample: .empty, velocity: 1))
        #expect(render(mixer, frames: 512).allSatisfy { $0 == 0 })
        #expect(mixer.activeVoiceCount == 0)
    }

    /// A full pattern is a dozen notes a second for as long as anyone plays.
    /// Nothing should creep: not the voice count, not the output level.
    @Test("A long busy run stays level and never runs out of voices")
    func sustainedLoad() {
        let sample = TestSample.tone(seconds: 0.4)
        let mixer = AudioMixer(sampleRate: rate)
        let blockFrames = 512
        var peak = 0.0

        // Roughly a minute of a dense pattern: 8 notes every 125 ms.
        var next: Int64 = 0
        for block in 0..<Int(rate * 60) / blockFrames {
            while next < mixer.frame + Int64(blockFrames) {
                for _ in 0..<8 {
                    mixer.schedule(
                        AudioEvent(
                            kind: .sampleHit, frame: next, sample: sample.ref,
                            rate: 1.5, velocity: 0.9, releaseScale: 0.5))
                }
                next += Int64(rate * 0.125)
            }
            let output = render(mixer, frames: blockFrames)
            if block > 20 { peak = max(peak, output.map(abs).max() ?? 0) }
        }

        #expect(peak > 0.05, "the mixer went quiet")
        #expect(peak < 1.2, "the limiter let it run away: \(peak)")
        #expect(mixer.queueOverflows == 0)
    }
}
