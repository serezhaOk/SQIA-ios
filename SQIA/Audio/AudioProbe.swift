// A bench for the audio foundation and the field, and nothing more.
//
// The sequencer screen does not exist yet, so this stands in for it: one
// sample, one fixed pattern, and the real engine, transport and renderer
// underneath. It is what the milestones are judged on — does it hold tempo
// for ten minutes, does it come back after a phone call, do the dots bloom
// exactly when their note lands — and it goes away when the sequencer
// arrives.
//
// Everything here avoids `lazy` and implicit `self`: the Observable macro
// rewrites stored properties into computed ones, which `lazy` cannot be, and
// older compilers will not take implicit `self` inside a nested closure.

import Foundation
import Observation
import SQIACore

@MainActor
@Observable
final class AudioProbe {
    private(set) var isPlaying = false
    private(set) var status = "idle"
    /// Row currently sounding, for the readout.
    private(set) var playhead = -1
    private(set) var stepsPlayed = 0
    private(set) var droppedNotes = 0
    private(set) var bpm: Double = 120

    /// What the field draws. The pattern is fixed, so a drift is a drift and
    /// not a different pattern.
    @ObservationIgnored let scene = FieldScene(
        grid: {
            var grid = NoteGrid()
            grid.randomize(using: Mulberry32(seed: 20_260_806))
            return grid
        }())

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private let sequencer: Sequencer

    /// A sample from the set. The voice list is synths-first and its sample
    /// entries are parked, exactly as in the web app, so the bench names one
    /// directly rather than pretending to pick from a menu.
    private static let benchSample = "bell-kalimbox"

    init() {
        let engine = AudioEngine()
        self.engine = engine
        sequencer = Sequencer(engine: engine)
    }

    // ------------------------------------------------------------- control --

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
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
                guard let self, self.isPlaying else { return }
                self.isPlaying = false
                self.sequencer.stop()
                self.status = "interrupted"
            }
        }
        engine.onRestarted = { [weak self] in
            Task { @MainActor in self?.status = "playing" }
        }

        // Everything the transport reads is captured by value here, so the
        // callback never reaches back into main-actor state from the
        // transport queue.
        let grid = scene.grid
        let rates = Music.rateTable(rootPc: 9, scale: Music.scales[0])
        let voice = VoiceKind.sample(rates: rates)
        let random = SystemRandomSource()
        let engine = engine

        sequencer.onStep = { [weak self] step, frame, lead in
            let mixer = engine.mixer
            let hits = StepVoicing.hits(step: step, in: grid, voice: voice, using: random)
            for hit in hits {
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

            // Bloom the dots exactly when their sound lands, not when it was
            // scheduled — the whole point of scheduling ahead.
            let lit = hits.map { ($0.column, $0.velocity) }
            let delay = max(0, lead)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    self?.land(step: step, lit: lit, mixer: mixer)
                }
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
        scene.playhead = -1
        status = "stopped"
    }

    func setTempo(_ value: Double) {
        bpm = Tempo.clamp(value)
        sequencer.bpm = bpm
    }

    func bumpTempo() {
        setTempo(Tempo.bump(bpm))
    }

    // -------------------------------------------------------------- arrival --

    private func land(step: Int, lit: [(Int, Double)], mixer: AudioMixer) {
        for (column, velocity) in lit {
            scene.flash(row: step, column: column, velocity: velocity)
        }
        scene.playhead = step
        playhead = step
        stepsPlayed += 1
        droppedNotes = mixer.droppedNotes
    }
}
