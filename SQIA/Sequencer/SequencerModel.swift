// The sequencer, wired up: the session state, the audio underneath it, and
// the field on top.
//
// The screen only ever calls the verbs here — paint, erase, cycle the key,
// scrub the tempo — and everything else follows from that.

import Foundation
import Observation
import SQIACore
import SwiftUI

/// What the transport needs in order to voice a step. Read on the transport
/// queue, written on the main thread after every edit.
///
/// A lock is fine here: this crossing is between the UI and a timer, not the
/// render thread, and it is held for the length of an array copy.
private final class VoicingBox: @unchecked Sendable {
    struct Track {
        var grid = NoteGrid()
        var muted = false
        var sample = SampleRef.empty
        var rates: [Double] = []
    }

    private let lock = NSLock()
    private var tracks: [Track] = []

    func read() -> [Track] {
        lock.lock()
        defer { lock.unlock() }
        return tracks
    }

    func write(_ value: [Track]) {
        lock.lock()
        tracks = value
        lock.unlock()
    }
}

@MainActor
@Observable
final class SequencerModel {
    private(set) var state: SequencerState
    /// The eraser clears a 2×2 block per touch instead of painting.
    private(set) var eraseMode = false
    private(set) var isLoadingVoice = false
    private(set) var isRunning = false
    private(set) var failure: String?

    /// One per track: each keeps its own blooms and ripples, so a track that
    /// is not on screen still has somewhere to put them.
    @ObservationIgnored let scenes: [FieldScene]

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private let sequencer: Sequencer
    @ObservationIgnored private let voicing = VoicingBox()
    @ObservationIgnored private let random = SystemRandomSource()

    @ObservationIgnored private var tempoDragStart: Double?
    @ObservationIgnored private var tempoDragMoved = false
    /// The layout the last frame was drawn with — what a touch is resolved
    /// against.
    @ObservationIgnored private var layout: FieldLayout?

    init() {
        let engine = AudioEngine()
        self.engine = engine
        sequencer = Sequencer(engine: engine)
        state = SequencerState.fresh(voices: VoiceCatalog.defaultVoices)
        scenes = (0..<SequencerState.trackCount).map { _ in FieldScene() }

        syncScenes()
        loadVoices()
        wireTransport()
    }

    // ------------------------------------------------------------- running --

    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
        } catch {
            failure = error.localizedDescription
            return
        }
        engine.onStopped = { [weak self] in
            Task { @MainActor in self?.handleEngineStopped() }
        }
        engine.onRestarted = { [weak self] in
            Task { @MainActor in self?.failure = nil }
        }
        sequencer.bpm = state.bpm
        sequencer.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        sequencer.stop()
        engine.stop()
        isRunning = false
        for scene in scenes { scene.playhead = -1 }
    }

    private func handleEngineStopped() {
        guard isRunning else { return }
        sequencer.stop()
        isRunning = false
        for scene in scenes { scene.playhead = -1 }
    }

    private func wireTransport() {
        let voicing = voicing
        let engine = engine
        let random = random

        sequencer.onStep = { [weak self] step, frame, lead in
            let mixer = engine.mixer
            let tracks = voicing.read()
            var lit: [(track: Int, column: Int, velocity: Double)] = []

            for (index, track) in tracks.enumerated() {
                // A muted track draws nothing from the random stream either,
                // which is what the web does.
                if track.muted { continue }
                let hits = StepVoicing.hits(
                    step: step, in: track.grid,
                    voice: .sample(rates: track.rates), using: random)
                for hit in hits {
                    mixer.schedule(
                        AudioEvent(
                            kind: .sampleHit,
                            frame: frame,
                            sample: track.sample,
                            rate: hit.rate ?? 1,
                            velocity: hit.velocity,
                            releaseScale: hit.releaseScale ?? 1
                        ))
                    lit.append((index, hit.column, hit.velocity))
                }
            }

            // Bloom the dots exactly when their sound lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, lead)) {
                Task { @MainActor in self?.land(step: step, lit: lit) }
            }
        }
    }

    private func land(step: Int, lit: [(track: Int, column: Int, velocity: Double)]) {
        for hit in lit where scenes.indices.contains(hit.track) {
            scenes[hit.track].flash(row: step, column: hit.column, velocity: hit.velocity)
        }
        for scene in scenes { scene.playhead = step }
    }

    // ---------------------------------------------------------- the drawing --

    /// The layers the renderer draws. Full screen, active track only, until
    /// the mixer arrives.
    func layers(in rect: CGRect) -> [FieldLayer] {
        layout = Field.layout(
            x: Double(rect.minX), y: Double(rect.minY),
            width: Double(rect.width), height: Double(rect.height))
        return [scenes[state.activeTrackIndex].layer(in: rect)]
    }

    /// A finger on the field: paint, or erase where the eraser is on.
    func touch(at point: CGPoint) {
        guard let layout else { return }
        if eraseMode {
            guard let cell = Field.hit(x: Double(point.x), y: Double(point.y), in: layout)
            else { return }
            state.erase(row: cell.row, column: cell.column)
        } else {
            guard
                let position = Field.position(
                    x: Double(point.x), y: Double(point.y), in: layout)
            else { return }
            state.brush(gx: position.gx, gy: position.gy)
        }
        syncScenes()
        publishVoicing()
    }

    func toggleErase() {
        eraseMode.toggle()
    }

    func randomize() {
        state.randomize(using: random)
        syncScenes()
        publishVoicing()
    }

    // -------------------------------------------------------------- the key --

    func cycleRoot() {
        state.cycleRoot()
        publishVoicing()
    }

    func cycleScale() {
        state.cycleScale()
        publishVoicing()
    }

    func cycleTrack() {
        state.cycleTrack()
    }

    // ------------------------------------------------------------ the tempo --

    func scrubTempo(dx: CGFloat) {
        if tempoDragStart == nil {
            tempoDragStart = state.bpm
            tempoDragMoved = false
        }
        guard let start = tempoDragStart else { return }
        if abs(Double(dx)) > Tempo.dragThreshold { tempoDragMoved = true }
        setTempo(Tempo.scrub(from: start, dx: Double(dx)))
    }

    /// A drag that never moved is a tap, and a tap bumps.
    func endTempoDrag() {
        if !tempoDragMoved { setTempo(Tempo.bump(state.bpm)) }
        tempoDragStart = nil
        tempoDragMoved = false
    }

    private func setTempo(_ value: Double) {
        state.bpm = Tempo.clamp(value)
        sequencer.bpm = state.bpm
    }

    // ------------------------------------------------------------ the voice --

    var activeVoiceLabel: String {
        VoiceCatalog.label(at: state.activeTrack.voiceIndex)
    }

    func selectVoice(_ index: Int) {
        guard index != state.activeTrack.voiceIndex else { return }
        state.activeTrack.voiceIndex = index
        loadVoices()
    }

    /// Decode whatever the tracks are set to, then republish.
    ///
    /// Decoding reads a file, which is not something to do on the main
    /// thread, so the label dims until the sound is ready — the same as the
    /// web app's loading state.
    private func loadVoices() {
        let wanted = state.tracks.map { VoiceCatalog.voice(at: $0.voiceIndex).file }
        if wanted.allSatisfy(SampleLibrary.shared.isLoaded) {
            publishVoicing()
            return
        }

        isLoadingVoice = true
        Task.detached(priority: .userInitiated) { [weak self] in
            for file in wanted { _ = SampleLibrary.shared.sample(named: file) }
            await MainActor.run {
                guard let self else { return }
                self.isLoadingVoice = false
                self.publishVoicing()
            }
        }
    }

    // ------------------------------------------------------------ plumbing --

    /// Hand the field its copy of the patterns. The animator keeps its own
    /// blooms; only the notes come from here.
    private func syncScenes() {
        for (index, track) in state.tracks.enumerated() where scenes.indices.contains(index) {
            scenes[index].grid = track.grid
            scenes[index].alpha = track.muted ? 0.35 : 1
        }
    }

    /// Every stroke of a finger comes through here, so it only ever reads
    /// what is already decoded — a track whose sound is still loading stays
    /// silent for a moment rather than blocking the drawing.
    private func publishVoicing() {
        voicing.write(
            state.tracks.map { track in
                let voice = VoiceCatalog.voice(at: track.voiceIndex)
                return VoicingBox.Track(
                    grid: track.grid,
                    muted: track.muted,
                    sample: SampleLibrary.shared.cached(voice.file) ?? .empty,
                    rates: state.rateTable(baseMidi: voice.baseMidi)
                )
            })
    }
}
