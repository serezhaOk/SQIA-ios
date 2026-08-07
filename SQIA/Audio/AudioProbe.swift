// A bench for the audio foundation, and nothing more.
//
// The sequencer screen does not exist yet, so this stands in for it: one
// sample, one fixed pattern, and the real engine, transport and renderer
// underneath. It is what the milestone is judged on — does it hold tempo for
// ten minutes, does it come back after a phone call, does it survive
// AirPods — and it goes away when the sequencer arrives.

import Foundation
import Observation
import SQIACore

@MainActor
@Observable
final class AudioProbe {
    private(set) var isPlaying = false
    private(set) var status = "idle"
    /// Row currently sounding, for the field to light up.
    private(set) var playhead = -1
    private(set) var stepsPlayed = 0
    private(set) var droppedNotes = 0

    var bpm: Double = 120 {
        didSet { sequencer.bpm = bpm }
    }

    /// The pattern the bench plays. Fixed, so a drift is a drift and not a
    /// different pattern.
    private(set) var pattern: NoteGrid = {
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: 20_260_806))
        return grid
    }()

    private let engine = AudioEngine()
    private lazy var sequencer = Sequencer(engine: engine)

    /// A sample from the set. The voice list is synths-first and its sample
    /// entries are parked, exactly as in the web app, so the bench names one
    /// directly rather than pretending to pick from a menu.
    private static let benchSample = "bell-kalimbox"

    func toggle() {
        isPlaying ? stop() : start()
    }

    func start() {
        guard !isPlaying else { return }

        guard let sample = SampleLibrary.shared.sample(named: Self.benchSample) else {
            status = "sample \(Self.benchSample).wav did not load"
            return
        }

        do {
            try engine.start()
        } catch {
            status = "engine did not start: \(error.localizedDescription)"
            return
        }

        // The engine can stop on its own — a call, headphones out — and the
        // UI has to follow rather than claim to still be playing.
        engine.onStopped = { [weak self] in
            Task { @MainActor in
                guard let self, isPlaying else { return }
                isPlaying = false
                sequencer.stop()
                status = "interrupted"
            }
        }
        engine.onRestarted = { [weak self] in
            Task { @MainActor in self?.status = "playing" }
        }

        // Everything the transport reads is captured by value here, so the
        // callback never reaches back into main-actor state from the
        // transport queue.
        let grid = pattern
        let rates = Music.rateTable(rootPc: 9, scale: Music.scales[0])
        let voice = VoiceKind.sample(rates: rates)
        let random = SystemRandomSource()
        let engine = engine

        sequencer.onStep = { [weak self] step, frame, lead in
            let mixer = engine.mixer
            for hit in StepVoicing.hits(step: step, in: grid, voice: voice, using: random) {
                mixer.schedule(
                    AudioEvent(
                        kind: .sampleHit,
                        frame: frame,
                        sample: sample,
                        rate: hit.rate ?? 1,
                        velocity: hit.velocity,
                        releaseScale: hit.releaseScale ?? 1
                    ))
            }

            // Light the row when the note lands, not when it was scheduled.
            let delay = max(0, lead)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in self?.advance(to: step, mixer: mixer) }
            }
        }

        sequencer.bpm = bpm
        sequencer.start()
        isPlaying = true
        status = "playing"
    }

    func stop() {
        sequencer.stop()
        engine.stop()
        isPlaying = false
        playhead = -1
        status = "stopped"
    }

    func bumpTempo() {
        bpm = Tempo.bump(bpm)
    }

    private func advance(to step: Int, mixer: AudioMixer) {
        playhead = step
        stepsPlayed += 1
        droppedNotes = mixer.droppedNotes
    }
}
