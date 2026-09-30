// The sequencer: the mixer, and a track opened out of it.
//
// Two screens in a stack. The mixer is the root — every track behind its
// own pane of glass, one above the other — and a track is a screen pushed
// over it that zooms out of
// its own panel and shrinks back into it, cut to the panel's corners the
// whole way, as a photo does out of a grid. It used to be one screen that
// flew its field between full size and a slot on a clock of its own; the
// system's zoom is the gesture a phone already knows, and it can be dragged
// shut halfway and let go.
//
// Opening a project lands on its track with the mixer already underneath, so
// the first thing on screen is still something to draw on.
//
// The second pane is SQIA Plus. Without it the pane holds the diamond and
// "+ Add track", and pressing it brings up the paywall instead of the track.
//
// The mixer alone has the transport, between the tempo and the key: a play
// button while the pattern is stopped, and a small pulsing wave while it
// plays that pauses it when pressed.
//
// Tempo and key across the top of both, the field in the middle, the eraser,
// the sound and the randomiser along the bottom of a track — laid out and
// styled from the Figma. Everything raised is one part wearing different
// colours: `ControlPill` and `BloomButtonStyle` in SequencerControls.swift.

import SQIACore
import SwiftUI

struct SequencerView: View {
    let model: SequencerModel
    let plus: PlusStore
    /// Flush what is owed and go back to the library.
    var onLeave: @MainActor () async -> Void

    /// Empty is the mixer; one index is that track, opened over it.
    @State private var path: [Int]
    /// Whether the mixer's field is drawing at full rate. It slows once a
    /// track has covered it and speeds up the moment one begins to leave.
    @State private var mixerLive: Bool
    @State private var showingVoices = false
    @State private var showingKey = false
    @State private var showingTempo = false
    @State private var showingPaywall = false
    /// Paused from the mixer's transport. Coming back to the app does not
    /// start what somebody stopped.
    @State private var paused = false
    /// The line above the field. Set by an action, cleared by its own task.
    @State private var announcement: String?
    @State private var announcing: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Preferences.backgroundPlayback) private var playsInBackground = false
    @Namespace private var zoom

    init(
        model: SequencerModel, plus: PlusStore,
        onLeave: @escaping @MainActor () async -> Void
    ) {
        self.model = model
        self.plus = plus
        self.onLeave = onLeave
        _path = State(initialValue: [model.state.activeTrackIndex])
        _mixerLive = State(initialValue: false)
    }

    /// The ground a track stands on. The mixer wears `opened`.
    private var palette: SequencerPalette { model.palette }

    var body: some View {
        NavigationStack(path: $path) {
            mixer
                .navigationDestination(for: Int.self) { index in
                    track
                        .zoomsOut(of: index, in: zoom)
                }
        }
        .sheet(isPresented: $showingTempo) {
            TempoSheet(
                bpm: model.state.bpm,
                onChange: { model.selectTempo($0) },
                palette: palette
            )
        }
        .sheet(isPresented: $showingVoices) {
            VoiceSheet(
                model: model,
                onPick: { preset in
                    model.selectVoice(preset)
                    showingVoices = false
                }
            )
        }
        .sheet(isPresented: $showingKey) {
            KeySheet(
                rootPc: model.state.rootPc,
                scaleIndex: model.state.scaleIndex,
                octave: model.state.octave,
                onPickOctave: { model.selectOctave($0) },
                onPickRoot: { model.selectRoot($0) },
                onPickScale: { model.selectScale($0) }
            )
        }
        .sheet(isPresented: $showingPaywall) {
            PlusPaywall(plus: plus)
        }
        .onAppear {
            model.start()
            Haptics.warm()
        }
        .onChange(of: model.access) {
            // Plus lapsed with its track open: back out to the mixer, where
            // the panel now shows why.
            if let index = path.first, model.isLocked(index) { path.removeAll() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounded, the app goes quiet — the same as a browser tab
            // losing its audio context — unless the profile's switch says
            // to play on.
            if phase == .active {
                if !paused { model.start() }
            } else if !(playsInBackground && plus.access.allows(.backgroundPlayback)) {
                model.stop()
            }
        }
        .task(id: path.isEmpty) {
            if path.isEmpty {
                mixerLive = true
                return
            }
            // Not at once: the mixer is still in view around the track for
            // as long as the zoom takes to fill the screen.
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            mixerLive = false
        }
        .overlay(alignment: .bottom) {
            if let failure = model.failure {
                Text(failure)
                    .manrope(.regular, TextStyle.messageSize)
                    .foregroundStyle(Palette.failure)
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: model.failure)
    }

    private func open(_ index: Int) {
        guard path.isEmpty else { return }
        Haptics.toggle()
        if model.isLocked(index) {
            showingPaywall = true
            return
        }
        model.selectTrack(index)
        path = [index]
    }

    // ------------------------------------------------------------- screens --

    private var mixer: some View {
        VStack(spacing: 0) {
            header(middle: false, transport: true)
            mixerStage
            // The toolbar is kept, invisibly, so the stage is exactly the
            // size it is on a track and the panels sit where the track
            // shrinks back to. The tile takes the band it leaves.
            toolbar
                .hidden()
                .overlay { backTile }
        }
        .background(GrainGround(ground: palette.opened.background).ignoresSafeArea())
        .environment(\.sequencerPalette, palette.opened)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var track: some View {
        VStack(spacing: 0) {
            header(middle: true)
            trackStage
            toolbar
                // The eraser's own bloom fades on, and the line above the
                // field fades in; the two tools it switches off have to go
                // at the same pace or the mode arrives in three pieces.
                .animation(Motion.fade, value: model.eraseMode)
        }
        .background(palette.background.ignoresSafeArea())
        .environment(\.sequencerPalette, palette)
        .toolbar(.hidden, for: .navigationBar)
    }

    // -------------------------------------------------------------- header --

    private func header(middle: Bool, transport: Bool = false) -> some View {
        HStack(spacing: 0) {
            tempoPill
            Spacer(minLength: 8)
            if middle {
                middleSlot
                    .animation(Motion.fade, value: currentAnnouncement)
                Spacer(minLength: 8)
            } else if transport {
                transportButton
                Spacer(minLength: 8)
            }
            keyPill
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    /// Drag sideways to scrub, tap to open the wheel.
    private var tempoPill: some View {
        ControlPill(width: 90) {
            Text("\(Int(model.state.bpm)) bpm")
                .manrope(.medium, 15, tracking: 0)
                .foregroundStyle(palette.label)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { model.scrubTempo(dx: $0.translation.width) }
                .onEnded { _ in
                    if model.endTempoDrag() {
                        Haptics.tap()
                        showingTempo = true
                    }
                }
        )
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(Int(model.state.bpm)) beats per minute")
        // A drag is not a gesture VoiceOver has, so the tempo would
        // otherwise be readable and unreachable.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.nudgeTempo(by: 5)
            case .decrement: model.nudgeTempo(by: -5)
            @unknown default: break
            }
        }
    }

    /// The scale name that renders widest, so the pill can be cut to it once
    /// and never resize as the key changes.
    private static let widestScaleName =
        Music.scales.map(\.name).max(by: { $0.count < $1.count }) ?? "phrygian"

    private var keyPill: some View {
        Button {
            Haptics.tap()
            showingKey = true
        } label: {
            // No fixed width and no shrinking: the pill is cut to the widest
            // label it can ever show — every root against the longest scale
            // — so "A# phrygian" fits at full size and a shorter key sits
            // centred in the same width rather than the box breathing in and
            // out under the finger.
            ControlPill {
                ZStack {
                    ForEach(Music.noteNames.indices, id: \.self) { pc in
                        Text("\(Music.noteNames[pc]) \(Self.widestScaleName)")
                            .manrope(.medium, 15, tracking: 0)
                            .lineLimit(1)
                            .hidden()
                    }
                    Text("\(model.state.rootName) \(model.state.scale.name)")
                        .manrope(.medium, 15, tracking: 0)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressFade())
        .accessibilityLabel("Key")
        .accessibilityValue(keyDescription)
    }

    /// The pill shows the key alone and keeps its width; the octave, when
    /// it is not the home one, is spoken rather than squeezed in.
    private var keyDescription: String {
        let key = "\(model.state.rootName) \(model.state.scale.name)"
        let octave = model.state.octave
        guard octave != 0 else { return key }
        return "\(key), octave \(KeySheet.octaveLabel(octave))"
    }

    /// The track dots, or whatever the screen has to say instead.
    ///
    /// One slot rather than two: a message and the dots never want the
    /// middle at the same time, and the design puts both there.
    @ViewBuilder
    private var middleSlot: some View {
        if let line = currentAnnouncement {
            Text(line)
                .manrope(.medium, 15, tracking: 0)
                .foregroundStyle(palette.label)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            trackDots
        }
    }

    /// Play while stopped; the wave while playing, which pauses.
    private var transportButton: some View {
        Button {
            Haptics.toggle()
            if model.isRunning {
                paused = true
                model.stop()
            } else {
                paused = false
                model.start()
            }
        } label: {
            ZStack {
                if model.isRunning {
                    PlayingWave(model: model)
                        .transition(.opacity)
                } else {
                    Image("PlayIcon")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .transition(.opacity)
                }
            }
            .frame(width: 72, height: 40)
            .contentShape(Rectangle())
            .animation(Motion.fade, value: model.isRunning)
        }
        .buttonStyle(PressFade())
        .accessibilityLabel(model.isRunning ? "Pause" : "Play")
    }

    private var currentAnnouncement: String? {
        model.eraseMode ? "Eraser is on" : announcement
    }

    /// One dot per track, the active one bright. Tapping goes back out to
    /// the mixer — the track shrinks into its panel.
    private var trackDots: some View {
        Button {
            Haptics.toggle()
            path.removeAll()
        } label: {
            HStack(spacing: 7) {
                ForEach(0..<SequencerState.trackCount, id: \.self) { index in
                    Capsule()
                        .fill(palette.label)
                        .opacity(index == model.state.activeTrackIndex ? 1 : 0.2)
                        .frame(width: 9, height: 15)
                }
            }
            .padding(8)
        }
        .buttonStyle(PressFade())
        .accessibilityLabel("Tracks")
    }

    // --------------------------------------------------------------- stage --

    private var trackStage: some View {
        FieldView(
            frame: { rect, dt in model.trackFrame(in: rect, dt: dt) },
            onTouch: { model.touch(at: $0) }
        )
        // The largest thing on the screen, and without this it is an
        // unnamed rectangle. Painting is a drag, which VoiceOver does not
        // have — so the hint says what it is for rather than pretending it
        // can be operated.
        .accessibilityElement()
        .accessibilityLabel("Note field")
        .accessibilityHint("Drag to draw notes. Use Shuffle below to fill it.")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Every track behind its pane, drawn by one field, with a tap target
    /// over each pane that the track zooms out of — and the two effect knobs
    /// under them.
    private var mixerStage: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                FieldView(
                    frame: { rect, dt in model.mixerFrame(in: rect, dt: dt) },
                    isResting: !mixerLive,
                    isTranslucent: true
                )
                .accessibilityHidden(true)

                ForEach(0..<SequencerState.trackCount, id: \.self) { index in
                    let panel = CGRect(model.mixerPanel(index, in: geometry.size))
                    if panel.width > 0 {
                        tile(index, in: panel)
                    }
                }

                effectKnobs(in: geometry.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A pane, as something to press. The field and the glass under it are
    /// Metal and cannot be the zoom's source themselves, so this is: a shape
    /// exactly the pane's size and corner, clear except while it is held.
    private func tile(_ index: Int, in panel: CGRect) -> some View {
        ZStack(alignment: .top) {
            Button {
                open(index)
            } label: {
                Color.clear
                    .contentShape(panelShape)
            }
            .buttonStyle(TilePress(shape: panelShape))
            .zoomSource(index, in: zoom, shape: panelShape)
            .accessibilityLabel("Track \(index + 1)")
            .accessibilityValue(model.isLocked(index) ? "SQIA Plus" : model.voiceLabel(index))
            .accessibilityHint(
                model.isLocked(index) ? "Shows what SQIA Plus opens." : "Opens this track.")

            if model.isLocked(index) {
                lockedPane
            } else {
                paneHeader(index)
            }
        }
        .frame(width: panel.width, height: panel.height)
        .position(x: panel.midX, y: panel.midY)
    }

    /// Scatter and Delay side by side under the panes, each in half of the
    /// row the design lays out: 20 in from a 351-wide strip down the middle.
    private func effectKnobs(in size: CGSize) -> some View {
        let last = CGRect(model.mixerPanel(SequencerState.trackCount - 1, in: size))
        let top = last.maxY + MixerLayout.knobsGap
        let effects: [MasterEffect] = [.scatter, .delay]

        return HStack(spacing: 0) {
            ForEach(effects, id: \.self) { effect in
                EffectKnob(
                    title: effect.name,
                    value: model.state.effects[effect],
                    onChange: { model.setEffect(effect, to: $0) }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: min(351, size.width - 24), height: EffectKnob.height)
        .position(x: size.width / 2, y: top + EffectKnob.height / 2)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MixerLayout.stackCorner, style: .continuous)
    }

    /// The voice's name and its mute, across the top of the pane. The name
    /// is only a picture — a press on it lands on the pane and opens it.
    private func paneHeader(_ index: Int) -> some View {
        let muted = model.isMuted(index)
        return HStack(spacing: 0) {
            // "Machine", as the design writes it, rather than the web's
            // capitals the picker uses.
            Text(model.voiceLabel(index).capitalized)
                .manrope(.medium, 15.18, tracking: 0)
                .foregroundStyle(.white)
                .lineLimit(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                model.toggleMute(index)
            } label: {
                Image("MuteIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18.35, height: 17.27)
                    .foregroundStyle(muted ? Color(hex: 0x101010) : .white)
                    .frame(width: 32, height: 32)
                    .background(muted ? Color.white : palette.surface, in: Circle())
                    .overlay { Circle().strokeBorder(palette.hairline, lineWidth: 1) }
                    .innerBloom(muted ? .clear : palette.bloom)
                    .clipShape(Circle())
                    .animation(Motion.fade, value: muted)
                    // A bigger target than the drawing.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            .accessibilityLabel(muted ? "Unmute \(model.voiceLabel(index))" : "Mute \(model.voiceLabel(index))")
            .accessibilityAddTraits(muted ? [.isSelected] : [])
            .padding(.trailing, -6)
        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .frame(height: 64)
    }

    /// A pane Plus has not opened: the diamond, and what it would add.
    private var lockedPane: some View {
        VStack(spacing: 16) {
            PlusBadge(size: 32)
            Text("+ Add track")
                .manrope(.medium, 15.18, tracking: 0)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // -------------------------------------------------------------- footer --

    private var backTile: some View {
        Button {
            // Edits already autosave; this flushes and returns.
            Haptics.toggle()
            Task { await onLeave() }
        } label: {
            ControlPill(width: 175, height: 50) {
                Text("Back to projects")
                    .manrope(.semibold, 15, tracking: 0.01)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(PressFade())
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            eraseButton
            Spacer(minLength: 8)
            voicePill
            Spacer(minLength: 8)
            shuffleButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    /// A mode, so it stays lit for as long as it is on.
    private var eraseButton: some View {
        Button {
            Haptics.toggle()
            model.toggleErase()
        } label: {
            ControlIcon(name: "EraserIcon")
        }
        .buttonStyle(
            BloomButtonStyle(
                onColor: palette.eraseBloom,
                pressColor: palette.eraseBloom,
                isOn: model.eraseMode,
                tint: model.eraseMode
                    ? palette.eraseBloom : palette.label
            )
        )
        .accessibilityLabel("Erase")
        .accessibilityAddTraits(model.eraseMode ? [.isSelected] : [])
    }

    private var voicePill: some View {
        Button {
            Haptics.tap()
            showingVoices = true
        } label: {
            ControlPill(width: 124, height: 46) {
                Text(model.activeVoiceLabel)
                    .manrope(.medium, 15, tracking: 0)
                    .foregroundStyle(palette.pillLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(PressFade())
        .opacity(model.eraseMode ? palette.dimmed : 1)
        .disabled(model.eraseMode)
        .accessibilityLabel("Sound")
        .accessibilityValue(model.activeVoiceLabel)
    }

    /// An action, so it lights only while it is held and says what it did
    /// above the field for a moment afterwards.
    private var shuffleButton: some View {
        Button {
            model.randomize()
            announce("Shuffle track")
        } label: {
            ControlIcon(name: "ShuffleIcon")
        }
        .buttonStyle(
            BloomButtonStyle(
                onColor: nil,
                pressColor: palette.shuffleBloom,
                isOn: false
            )
        )
        .opacity(model.eraseMode ? palette.dimmed : 1)
        .disabled(model.eraseMode)
        // "Shuffle", not "Shuffle track": the line it puts above the field
        // says that, and two elements answering to one name is a thing
        // VoiceOver has no way to tell apart.
        .accessibilityLabel("Shuffle")
        .accessibilityHint("Fills this track with a new pattern.")
    }

    private func announce(_ line: String) {
        announcing?.cancel()
        announcement = line
        announcing = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            announcement = nil
        }
    }
}

/// The web dims a label while it is held rather than tinting it.
struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A panel under the finger. What it holds is drawn by Metal beneath, so
/// the press cannot dim it — it lays a faint wash over it instead.
private struct TilePress: ButtonStyle {
    let shape: RoundedRectangle
    @Environment(\.sequencerPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                shape.fill(palette.label.opacity(configuration.isPressed ? 0.08 : 0))
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// ------------------------------------------------------------------ zoom --

/// The system's zoom is iOS 18. Before it, a track is pushed the ordinary
/// way — still a screen of its own, just sliding rather than growing.
private extension View {
    @ViewBuilder
    func zoomSource(_ id: Int, in namespace: Namespace.ID, shape: RoundedRectangle)
        -> some View
    {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(shape)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomsOut(of id: Int, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

#Preview {
    SequencerView(
        model: SequencerModel(store: InMemoryProjectStore()), plus: PlusStore(), onLeave: {})
}

/// The mixer's transport while the pattern plays: nine bars, one per band of
/// the output from 60 Hz on the left to 10 kHz on the right, each as tall as
/// that band is loud. They jump up with a hit and fall back more slowly, the
/// way a level meter's needle does, so a beat reads as a beat.
private struct PlayingWave: View {
    let model: SequencerModel

    /// Carried from frame to frame, so a bar can fall rather than snap.
    @State private var smoother = Smoother()

    private static let tallest: CGFloat = 20
    private static let shortest: CGFloat = 4

    var body: some View {
        TimelineView(.animation) { timeline in
            let heights = smoother.step(model: model, at: timeline.date)
            HStack(spacing: 2) {
                ForEach(heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white)
                        .frame(
                            width: 4,
                            height: Self.shortest
                                + (Self.tallest - Self.shortest) * CGFloat(heights[index]))
                }
            }
            .frame(height: Self.tallest)
        }
        .accessibilityHidden(true)
    }

    @MainActor
    final class Smoother {
        private var levels = [Double](repeating: 0, count: BandMeter.bands)
        private var shown = [Double](repeating: 0, count: BandMeter.bands)
        private var last: Date?

        func step(model: SequencerModel, at now: Date) -> [Double] {
            let dt = min(max(now.timeIntervalSince(last ?? now), 0), 0.1)
            last = now
            model.outputBands(into: &levels)
            // Up in about 30 ms, down in about 250.
            let rise = 1 - exp(-dt / 0.03)
            let fall = 1 - exp(-dt / 0.25)
            for band in shown.indices {
                let target = levels[band]
                shown[band] += (target - shown[band]) * (target > shown[band] ? rise : fall)
            }
            return shown
        }
    }
}
