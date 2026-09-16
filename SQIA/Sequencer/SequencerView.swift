// The sequencer: the mixer, and a track opened out of it.
//
// Two screens in a stack. The mixer is the root — every track in its panel,
// side by side — and a track is a screen pushed over it that zooms out of
// its own panel and shrinks back into it, cut to the panel's corners the
// whole way, as a photo does out of a grid. It used to be one screen that
// flew its field between full size and a slot on a clock of its own; the
// system's zoom is the gesture a phone already knows, and it can be dragged
// shut halfway and let go.
//
// Opening a project lands on its track with the mixer already underneath, so
// the first thing on screen is still something to draw on.
//
// Tempo and key across the top of both, the field in the middle, the eraser,
// the sound and the randomiser along the bottom of a track — laid out and
// styled from the Figma. Everything raised is one part wearing different
// colours: `ControlPill` and `BloomButtonStyle` in SequencerControls.swift.

import SQIACore
import SwiftUI

struct SequencerView: View {
    let model: SequencerModel
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
    /// The line above the field. Set by an action, cleared by its own task.
    @State private var announcement: String?
    @State private var announcing: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoom

    init(model: SequencerModel, onLeave: @escaping @MainActor () async -> Void) {
        self.model = model
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
                onPickRoot: { model.selectRoot($0) },
                onPickScale: { model.selectScale($0) }
            )
        }
        .onAppear {
            model.start()
            Haptics.warm()
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounded, the app goes quiet — the same as a browser tab
            // losing its audio context.
            if phase == .active {
                model.start()
            } else {
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
        model.selectTrack(index)
        path = [index]
    }

    // ------------------------------------------------------------- screens --

    private var mixer: some View {
        VStack(spacing: 0) {
            header(middle: false)
            mixerStage
            // The toolbar is kept, invisibly, so the stage is exactly the
            // size it is on a track and the panels sit where the track
            // shrinks back to. The tile takes the band it leaves.
            toolbar
                .hidden()
                .overlay { backTile }
        }
        .background(palette.opened.background.ignoresSafeArea())
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

    private func header(middle: Bool) -> some View {
        HStack(spacing: 0) {
            tempoPill
            Spacer(minLength: 8)
            if middle {
                middleSlot
                    .animation(Motion.fade, value: currentAnnouncement)
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
        .accessibilityValue("\(model.state.rootName) \(model.state.scale.name)")
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

    /// Every track in its panel, drawn by one field, with a tap target over
    /// each panel that the track zooms out of.
    private var mixerStage: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                FieldView(
                    frame: { rect, dt in model.mixerFrame(in: rect, dt: dt) },
                    isResting: !mixerLive
                )
                .accessibilityHidden(true)

                ForEach(0..<SequencerState.trackCount, id: \.self) { index in
                    let panel = CGRect(model.mixerPanel(index, in: geometry.size))
                    if panel.width > 0 {
                        tile(index, in: panel)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A panel, as something to press. The field under it is Metal and
    /// cannot be the zoom's source itself, so this is: a shape exactly the
    /// panel's size and corner, clear except while it is held.
    private func tile(_ index: Int, in panel: CGRect) -> some View {
        ZStack(alignment: .bottom) {
            Button {
                open(index)
            } label: {
                Color.clear
                    .contentShape(panelShape)
            }
            .buttonStyle(TilePress(shape: panelShape))
            .zoomSource(index, in: zoom, shape: panelShape)
            .accessibilityLabel("Track \(index + 1)")
            .accessibilityValue(model.voiceLabel(index))
            .accessibilityHint("Opens this track.")

            if model.hasPart(index) {
                chipRow(index)
                    .padding(MixerLayout.chipInset)
            }
        }
        .frame(width: panel.width, height: panel.height)
        .position(x: panel.midX, y: panel.midY)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MixerLayout.corner, style: .circular)
    }

    /// The name and mute chips, pinned inside the panel over its last rows
    /// of dots.
    private func chipRow(_ index: Int) -> some View {
        let height = MixerLayout.chipHeight
        let chip = palette.opened
        return HStack(spacing: 0) {
            Button {
                open(index)
            } label: {
                Text(model.voiceLabel(index))
                    // The chip sets its tracking to zero, unlike the labels.
                    .manrope(.regular, 16, tracking: 0)
                    .foregroundStyle(chip.background)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: height)
                    .background(chip.label, in: Capsule())
            }
            .buttonStyle(PressFade())
            .accessibilityLabel("Open \(model.voiceLabel(index))")

            Spacer(minLength: 4)

            Button {
                Haptics.tap()
                model.toggleMute(index)
            } label: {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(
                        model.isMuted(index)
                            ? chip.background : chip.label
                    )
                    .frame(width: height, height: height)
                    .background(
                        model.isMuted(index)
                            ? chip.label : chip.label.opacity(0.1),
                        in: Capsule()
                    )
                    .animation(Motion.fade, value: model.isMuted(index))
            }
            .buttonStyle(PressFade())
            .accessibilityLabel(model.isMuted(index) ? "Unmute" : "Mute")
            .accessibilityAddTraits(model.isMuted(index) ? [.isSelected] : [])
        }
    }

    // -------------------------------------------------------------- footer --

    private var backTile: some View {
        Button {
            // Edits already autosave; this flushes and returns.
            Haptics.toggle()
            Task { await onLeave() }
        } label: {
            ControlPill(width: 335, height: 126) {
                Text("Back to projects")
                    .manrope(.medium, 15, tracking: 0)
                    .foregroundStyle(palette.pillLabel)
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
    SequencerView(model: SequencerModel(store: InMemoryProjectStore()), onLeave: {})
}
