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
        var preset = SynthPreset.reverie
        /// The MIDI note each column plays, in the current key.
        var midi: [Int] = []
    }

    private let lock = NSLock()
    private var tracks: [Track] = []
    private var storedBPM = SequencerState.defaultBPM
    private var storedTuning = Tuning.tuned

    /// Which subdivision each preset's echo currently sits on. Only the
    /// transport thread touches it, and only once a bar.
    var divisions = [Int](repeating: 0, count: SynthPreset.allCases.count)

    func read() -> (tracks: [Track], bpm: Double, tuning: Tuning) {
        lock.lock()
        defer { lock.unlock() }
        return (tracks, storedBPM, storedTuning)
    }

    func write(tuning: Tuning) {
        lock.lock()
        storedTuning = tuning
        lock.unlock()
    }

    func write(tracks: [Track], bpm: Double) {
        lock.lock()
        self.tracks = tracks
        storedBPM = bpm
        lock.unlock()
    }
}

@MainActor
@Observable
final class SequencerModel {
    private(set) var state: SequencerState
    /// The eraser clears a 2×2 block per touch instead of painting.
    private(set) var eraseMode = false
    private(set) var isRunning = false
    private(set) var failure: String?

    /// Whether the mixer is open. The travel between the two views is a
    /// separate number, because it is still on its way for a third of a
    /// second after this changes.
    private(set) var showingMixer = false
    @ObservationIgnored private var mixerTravel = 0.0
    /// The stage's size as of the last frame — what a touch is resolved
    /// against when the mixer is open.
    @ObservationIgnored private var stageSize = CGSize.zero
    /// Whether the touch now in progress has already done its one thing.
    @ObservationIgnored private var touchSpent = false

    /// One per track: each keeps its own blooms and ripples, so a track that
    /// is not on screen still has somewhere to put them.
    @ObservationIgnored let scenes: [FieldScene]

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private let sequencer: Sequencer
    @ObservationIgnored private let voicing = VoicingBox()
    @ObservationIgnored private let random = SystemRandomSource()

    #if DEBUG
        /// What the render thread is costing, live. A crackle is a deadline
        /// missed on the device, and nothing on a desk can see that happen —
        /// so while the sound is being tuned, the number is on screen. Debug
        /// builds only; it is not part of the app.
        private(set) var renderLoad = ""
        @ObservationIgnored private var loadTimer: Timer?

        /// When the binary now running was built. A stale build and a build
        /// that did not fix anything look exactly alike from across a room,
        /// and this is the difference.
        private static let builtAt: String = {
            guard
                let path = Bundle.main.executablePath,
                let date = try? FileManager.default.attributesOfItem(atPath: path)[
                    .modificationDate] as? Date
            else { return "?" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }()
    #endif

    /// What the panel has set. The transport reads its own copy through the
    /// box; this one is what the sliders are bound to.
    ///
    /// It outlives the app, because tuning by ear takes more than one
    /// sitting and losing an afternoon of it to a relaunch would be its own
    /// kind of bug.
    private(set) var tuning = Tuning.tuned
    private static let tuningKey = "sqia.tuning"

    // ------------------------------------------------------------ the row --
    /// The project being played, and the thing that writes it. Every edit
    /// goes through `publishVoicing`, which is also where the save is asked
    /// for — the same funnel the web uses, where `updateRates()` and
    /// `touch()` come as a pair.
    @ObservationIgnored private let store: any ProjectStore
    @ObservationIgnored private let autosave = Autosave()
    @ObservationIgnored private var projectId: String?

    @ObservationIgnored private var tempoDragStart: Double?
    @ObservationIgnored private var tempoDragMoved = false
    /// The layout the last frame was drawn with — what a touch is resolved
    /// against.
    @ObservationIgnored private var layout: FieldLayout?

    init(store: any ProjectStore) {
        self.store = store
        let engine = AudioEngine()
        self.engine = engine
        sequencer = Sequencer(engine: engine)
        state = SequencerState.fresh(voices: VoiceCatalog.defaultVoices)
        scenes = (0..<SequencerState.trackCount).map { _ in FieldScene() }

        if let saved = UserDefaults.standard.string(forKey: Self.tuningKey),
            let restored = Tuning.fromJSON(saved)
        {
            tuning = restored
        }

        syncScenes()
        publishVoicing(saving: false)
        wireTransport()
        voicing.write(tuning: tuning)
    }

    // ---------------------------------------------------------- the project --

    /// Load a saved project over whatever is on screen.
    func open(_ project: Project) {
        projectId = project.id
        state.apply(project.snapshot)
        sequencer.bpm = state.bpm
        syncScenes()
        publishVoicing(saving: false)
    }

    /// A blank field, with no row behind it yet. `adopt` gives it one once
    /// the library has written it.
    func startFresh() {
        projectId = nil
        state = SequencerState.fresh(voices: VoiceCatalog.defaultVoices)
        sequencer.bpm = state.bpm
        syncScenes()
        publishVoicing(saving: false)
    }

    func adopt(_ project: Project) {
        projectId = project.id
    }

    /// Leaving: stop, then write what is owed before the library redraws,
    /// so it does not show yesterday's card.
    func leave() async {
        stop()
        await autosave.flush()
    }

    /// Called for every edit. Building the snapshot is left to the moment
    /// the write actually happens — the web does the same, and it is the
    /// difference between copying five hundred cells once a second and
    /// copying them on every frame of a drag.
    private func noteEdit() {
        guard let id = projectId else { return }
        let store = store
        let autosave = autosave
        Task {
            await autosave.schedule { [weak self] in
                guard let self else { return }
                let snapshot = await self.snapshot
                try await store.save(id: id, snapshot: snapshot)
            }
        }
    }

    var snapshot: ProjectSnapshot { state.snapshot() }

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
            Task { @MainActor in
                self?.failure = nil
                self?.publishRoom()
                self?.publishChain(.machine)
            }
        }
        // A restored tuning, or a mixer rebuilt after a route change, both
        // start with everything at its defaults. Tell them where they are.
        publishRoom()
        publishChain(.machine)
        sequencer.bpm = state.bpm
        sequencer.start()
        isRunning = true
        startWatchingLoad()
    }

    func stop() {
        guard isRunning else { return }
        sequencer.stop()
        engine.stop()
        isRunning = false
        stopWatchingLoad()
        for scene in scenes { scene.playhead = -1 }
    }

    // ----------------------------------------------------------- the readout --

    private func startWatchingLoad() {
        #if DEBUG
            guard loadTimer == nil else { return }
            // Something on screen straight away, so an empty meter reads as
            // "not measured yet" rather than "this build has no meter".
            renderLoad = "\(Self.builtAt)  ·  AUD —"
            let timer = Timer(timeInterval: 0.5, repeats: true) {
                [weak self] _ in
                // Scheduled on the main run loop, so this is the main thread.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let mixer = self.engine.mixer
                    // audio · voices · frame · fps, and the faults only when
                    // there are any.
                    var text = String(
                        format: "%@  ·  AUD %.2f×  ·  %d voi",
                        Self.builtAt, mixer.renderLoad, mixer.soundingVoices)
                    if let renderer = FieldRenderer.onScreen {
                        text += String(
                            format: "  ·  UI %.1f ms  ·  %.0f fps",
                            renderer.frameCost, renderer.framesPerSecond)
                    }
                    let dropped = mixer.droppedNoteCount
                    if dropped > 0 { text += "  ·  \(dropped) cut" }
                    let blowups = mixer.recoveredBlowups
                    if blowups > 0 { text += "  ·  \(blowups) NaN" }
                    self.renderLoad = text
                }
            }
            // Common mode, so the number keeps moving while a finger is down
            // — which is exactly when the load is worth watching.
            RunLoop.main.add(timer, forMode: .common)
            loadTimer = timer
        #endif
    }

    private func stopWatchingLoad() {
        #if DEBUG
            loadTimer?.invalidate()
            loadTimer = nil
            renderLoad = ""
        #endif
    }

    private func handleEngineStopped() {
        guard isRunning else { return }
        sequencer.stop()
        isRunning = false
        stopWatchingLoad()
        for scene in scenes { scene.playhead = -1 }
    }

    private func wireTransport() {
        let voicing = voicing
        let engine = engine
        let random = random
        let sampleRate = engine.sampleRate
        // The echo is ducked across the bar line, so its drift has to arrive
        // before the bar it belongs to.
        let driftLead = Int(0.08 * sampleRate)

        sequencer.onStep = { [weak self] step, frame, lead in
            let mixer = engine.mixer
            let (tracks, bpm, tuning) = voicing.read()
            var lit: [(track: Int, column: Int, velocity: Double)] = []
            var drifted = Set<Int>()

            for (index, track) in tracks.enumerated() {
                // A muted track draws nothing from the random stream either,
                // which is what the web does.
                if track.muted { continue }

                // Once a bar, and once per preset however many tracks use
                // it, the chain wanders somewhere new.
                let presetIndex = track.preset.rawValue
                if step == 0 && !drifted.contains(presetIndex) {
                    drifted.insert(presetIndex)
                    var drift = SynthVoicing.drift(
                        preset: track.preset, bpm: bpm,
                        division: voicing.divisions[presetIndex], using: random)
                    if drift.echo > 0 {
                        voicing.divisions[presetIndex] =
                            Int((drift.echo / (60 / bpm / 4)).rounded())
                        drift.lead = driftLead
                    }
                    mixer.schedule(
                        AudioEvent.drift(drift, at: frame - Int64(driftLead)))
                }

                for hit in StepVoicing.hits(
                    step: step, in: track.grid, voice: .synth, using: random)
                {
                    let midi =
                        track.midi.indices.contains(hit.column) ? track.midi[hit.column] : 60
                    for voice in SynthVoicing.notes(
                        preset: track.preset, midi: midi, velocity: hit.velocity,
                        using: random, tuning: tuning)
                    {
                        mixer.schedule(
                            AudioEvent.note(
                                voice.recipe,
                                at: frame + Int64(voice.offset * sampleRate)))
                    }
                    lit.append((index, hit.column, hit.velocity))
                }
            }

            // Bloom the dots exactly when their sound lands — which is
            // two waits, not one. `lead` is how long until the mixer writes
            // the note into the buffer; the route then takes it a while
            // longer to reach the ear. Without the second half the picture
            // runs ahead of the sound by the buffer plus the route: barely
            // noticeable on the speaker, a fifth of a second on some
            // Bluetooth earbuds.
            //
            // Read per step rather than captured, because plugging in
            // headphones changes it mid-pattern.
            let travel = max(0, lead) + engine.outputLatency
            DispatchQueue.main.asyncAfter(deadline: .now() + travel) {
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

    /// What the renderer draws this frame.
    ///
    /// Full screen and one track while the mixer is shut; on the way open,
    /// the active track flies into its slot while the others fade up in
    /// theirs. The travel is advanced here rather than by a SwiftUI
    /// animation so that it runs on the display link the field already runs
    /// on — two clocks over a third of a second would visibly disagree.
    func frame(in rect: CGRect, dt: Double) -> FieldFrame {
        layout = Field.layout(
            x: Double(rect.minX), y: Double(rect.minY),
            width: Double(rect.width), height: Double(rect.height))
        stageSize = rect.size

        mixerTravel = MixerLayout.advance(
            mixerTravel, toward: showingMixer ? 1 : 0, dt: dt)
        let t = MixerLayout.ease(mixerTravel)
        let width = Double(rect.width)
        let height = Double(rect.height)

        // Shut, and nothing to animate: the sequencer as it was.
        if t <= 0.0001 {
            return FieldFrame(layers: [scenes[state.activeTrackIndex].layer(in: rect)])
        }

        var frame = FieldFrame()
        for index in state.tracks.indices where scenes.indices.contains(index) {
            let isActive = index == state.activeTrackIndex
            let alpha = MixerLayout.alpha(
                active: isActive, eased: t, muted: state.tracks[index].muted)
            if alpha <= 0.01 { continue }

            let panel = MixerLayout.rect(
                forTrack: index, active: state.activeTrackIndex,
                count: state.tracks.count, width: width, height: height, eased: t)

            var layer = scenes[index].layer(
                in: CGRect(x: panel.x, y: panel.y, width: panel.width, height: panel.height))
            layer.alpha = alpha
            layer.detail = MixerLayout.detail(active: isActive, eased: t)
            frame.layers.append(layer)
        }

        let outline = MixerLayout.outlineAlpha(eased: t)
        for index in state.tracks.indices {
            let slot = MixerLayout.panel(
                index, of: state.tracks.count, width: width, height: height)
            frame.outlines.append(
                FieldOutline(
                    rect: CGRect(
                        x: slot.x, y: slot.y, width: slot.width, height: slot.height),
                    alpha: outline))
        }
        return frame
    }

    /// Where the panels are, for the chips that sit inside them. Read by the
    /// view, which needs points rather than a draw list.
    func panel(_ index: Int) -> CGRect {
        guard let slot = slot(index) else { return .zero }
        return CGRect(x: slot.x, y: slot.y, width: slot.width, height: slot.height)
    }

    /// Where a panel's name and mute chips go — the arithmetic is the core's,
    /// so the view only has to place what it is handed.
    func chipStrip(_ index: Int) -> CGRect {
        guard let slot = slot(index) else { return .zero }
        let strip = MixerLayout.chips(in: slot)
        return CGRect(x: strip.x, y: strip.y, width: strip.width, height: strip.height)
    }

    private func slot(_ index: Int) -> Panel? {
        guard stageSize.width > 0, stageSize.height > 0 else { return nil }
        return MixerLayout.panel(
            index, of: state.tracks.count,
            width: Double(stageSize.width), height: Double(stageSize.height))
    }

    // -------------------------------------------------------------- mixer --

    func openMixer() {
        showingMixer = true
    }

    /// Pick a track and go back to it full screen — which is what tapping a
    /// panel does, and what the name chip on one does too.
    func openTrack(_ index: Int) {
        state.selectTrack(index)
        showingMixer = false
    }

    func toggleMute(_ index: Int) {
        guard state.tracks.indices.contains(index) else { return }
        state.tracks[index].muted.toggle()
        syncScenes()
        publishVoicing()
    }

    /// Only a track that holds a part gets a name and a mute button, as in
    /// the web — an empty panel is left clean.
    func hasPart(_ index: Int) -> Bool {
        state.tracks.indices.contains(index) && state.tracks[index].grid.hasNotes
    }

    func voiceLabel(_ index: Int) -> String {
        guard state.tracks.indices.contains(index) else { return "" }
        return VoiceCatalog.label(at: state.tracks[index].voiceIndex)
    }

    func isMuted(_ index: Int) -> Bool {
        state.tracks.indices.contains(index) && state.tracks[index].muted
    }

    /// A finger on the field: paint, or erase where the eraser is on. While
    /// the mixer is open it picks a track instead.
    ///
    /// A drag reports continuously, and picking a track shuts the mixer —
    /// so without a latch the same touch would choose a panel and then
    /// paint a dot on the track it had just opened.
    func touch(at point: CGPoint) {
        if showingMixer {
            guard !touchSpent else { return }
            touchSpent = true
            if let index = MixerLayout.hit(
                x: Double(point.x), y: Double(point.y),
                count: state.tracks.count,
                width: Double(stageSize.width), height: Double(stageSize.height))
            {
                openTrack(index)
            }
            return
        }
        guard !touchSpent else { return }
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

    /// The finger came up. Whatever this touch was for, it is over.
    func endTouch() {
        touchSpent = false
    }

    // ------------------------------------------------------------- tuning --

    func setTuning(_ knob: TuningKnob, to range: TunableRange) {
        guard tuning[knob] != range else { return }
        tuning[knob] = range
        publishTuning(knob)
    }

    func resetTuning(_ knob: TuningKnob) {
        guard tuning[knob] != Tuning.web[knob] else { return }
        tuning.reset(knob)
        publishTuning(knob)
    }

    func resetAllTuning() {
        guard !tuning.isDefault else { return }
        tuning.resetAll()
        publishTuning(.reverbDecay)
    }

    /// Back to the web's own numbers, for hearing what was moved away from.
    func resetToWeb() {
        guard !tuning.isWeb else { return }
        tuning.resetToWeb()
        publishTuning(.reverbDecay)
    }

    func applyTuning(json: String) -> Bool {
        guard let restored = Tuning.fromJSON(json) else { return false }
        tuning = restored
        publishTuning(.reverbDecay)
        return true
    }

    /// The room's three numbers live on the render thread, so they travel by
    /// event. Everything else is read fresh when the next note is rolled.
    private func publishTuning(_ knob: TuningKnob) {
        voicing.write(tuning: tuning)
        if tuning.isDefault {
            UserDefaults.standard.removeObject(forKey: Self.tuningKey)
        } else {
            UserDefaults.standard.set(tuning.json(), forKey: Self.tuningKey)
        }
        switch knob {
        case .reverbDecay, .reverbPreDelay, .reverbDamping:
            publishRoom()
        case .machineSendHighpass, .machineDelayWet:
            publishChain(.machine)
        case .machineFollowsKey:
            // The kit's layout is decided when a step is voiced, so this one
            // only has to reach the transport. It is not part of the project.
            publishVoicing(saving: false)
        default:
            break
        }
    }

    private func publishChain(_ preset: SynthPreset) {
        engine.mixer.schedule(
            AudioEvent.chain(
                ChainSettings(
                    preset: preset,
                    sendHighpass: tuning[.machineSendHighpass].lower,
                    delayWet: tuning[.machineDelayWet].lower)))
    }

    private func publishRoom() {
        engine.mixer.schedule(AudioEvent.room(RoomSettings(tuning)))
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

    func selectRoot(_ pc: Int) {
        guard pc != state.rootPc else { return }
        state.setRoot(pc)
        publishVoicing()
    }

    func selectScale(_ index: Int) {
        guard index != state.scaleIndex else { return }
        state.setScale(index)
        publishVoicing()
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
        publishVoicing()
    }

    // ------------------------------------------------------------ the voice --

    var activeVoiceLabel: String {
        VoiceCatalog.label(at: state.activeTrack.voiceIndex)
    }

    func selectVoice(_ preset: SynthPreset) {
        let index = VoiceCatalog.index(of: preset)
        guard index != state.activeTrack.voiceIndex else { return }
        state.activeTrack.voiceIndex = index
        publishVoicing()
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

    /// Hand the transport the patterns, and ask for a save.
    ///
    /// These two travel together because every edit needs both — the same
    /// `updateRates(); touch();` pair the web writes at each call site. The
    /// tuning panel is the one caller that changes how a note sounds without
    /// changing the project, so it passes `saving: false`.
    private func publishVoicing(saving: Bool = true) {
        if saving { noteEdit() }
        let midi = state.midiTable
        // A drum kit is not in a key. MACHINE picks its instrument from the
        // note's pitch class, so transposing it slides the whole kit between
        // columns — the kicks somebody drew become toms. Unless the panel
        // says to follow the key, drums get a chromatic run instead, where a
        // column is always the same instrument.
        let drums = tuning.isOn(.machineFollowsKey) ? midi : Music.drumTable
        voicing.write(
            tracks: state.tracks.map { track in
                let preset = VoiceCatalog.preset(at: track.voiceIndex)
                return VoicingBox.Track(
                    grid: track.grid,
                    muted: track.muted,
                    preset: preset,
                    midi: preset == .machine ? drums : midi
                )
            },
            bpm: state.bpm)
    }
}
