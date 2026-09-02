// The sequencer screen.
//
// Tempo and key across the top, the field in the middle, the eraser, the
// sound and the randomiser along the bottom — laid out and styled from the
// Figma rather than from the web's style.css, which is where this screen
// stops being a port.
//
// Everything raised is one part wearing different colours: `ControlPill` and
// `BloomButtonStyle` in SequencerControls.swift. The two icon buttons light
// for different reasons and that difference is the design's, not an
// accident — the eraser is a mode and stays lit, the shuffle is an action
// and lights only under the finger.

import SQIACore
import SwiftUI

struct SequencerView: View {
    let model: SequencerModel
    /// Flush what is owed and go back to the library.
    var onLeave: @MainActor () async -> Void

    @State private var showingVoices = false
    @State private var showingKey = false
    @State private var showingTempo = false
    /// The line above the field. Set by an action, cleared by its own task.
    @State private var announcement: String?
    @State private var announcing: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    /// Which ground the screen is standing on. Read from the model here and
    /// handed to everything below in the environment, so a control never has
    /// to be told twice.
    private var palette: SequencerPalette { model.palette }

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            footer
        }
        .background {
            // The bars stand on whatever the stage between them stands on:
            // the field's own black while the sequencer has the screen, the
            // mixer's grey once the panels are cards on it. They take the
            // same third of a second the panels take to fly, so the card
            // growing back into a screen and the ground going out from under
            // it happen as one move rather than as a switch and then a move.
            palette.background
                .ignoresSafeArea()
                .animation(
                    .easeInOut(duration: MixerLayout.transition),
                    value: model.showingMixer)
        }
        .overlay(alignment: .top) {
            if showingTempo {
                TempoWheelOverlay(
                    bpm: model.state.bpm,
                    onChange: { model.selectTempo($0) },
                    onClose: { showingTempo = false }
                )
            }
        }
        .animation(.easeOut(duration: 0.22), value: showingTempo)
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
        .overlay(alignment: .bottom) {
            if let failure = model.failure {
                Text(failure)
                    .manrope(.regular, TextStyle.messageSize)
                    .foregroundStyle(Palette.failure)
                    .padding(12)
            }
        }
        // Last, so it wraps the overlays too: the environment travels
        // inward, and the tempo card is placed over this screen rather than
        // inside it.
        .environment(\.sequencerPalette, palette)
    }

    // -------------------------------------------------------------- header --

    private var header: some View {
        HStack(spacing: 0) {
            tempoPill
            Spacer(minLength: 8)
            middleSlot
                .animation(.easeInOut(duration: 0.2), value: currentAnnouncement)
            Spacer(minLength: 8)
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

    private var keyPill: some View {
        Button {
            Haptics.tap()
            showingKey = true
        } label: {
            ControlPill(width: 90) {
                Text("\(model.state.rootName) \(model.state.scale.name)")
                    .manrope(.medium, 15, tracking: 0)
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    /// One dot per track, the active one bright. Tapping opens the mixer,
    /// as in the web — and the control goes away while it is open, because
    /// there is nothing left for it to do.
    private var trackDots: some View {
        Button {
            Haptics.toggle()
            model.openMixer()
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
        .opacity(model.showingMixer ? 0 : 1)
        .disabled(model.showingMixer)
        .animation(.easeInOut(duration: 0.18), value: model.showingMixer)
    }

    // --------------------------------------------------------------- stage --

    private var stage: some View {
        GeometryReader { geometry in
            FieldView { rect, dt in model.frame(in: rect, dt: dt) }
                .contentShape(Rectangle())
                .gesture(
                    // No minimum distance, so a tap paints as surely as a
                    // drag does. With the mixer open the same gesture picks
                    // a panel instead of painting.
                    DragGesture(minimumDistance: 0)
                        .onChanged { model.touch(at: $0.location) }
                        .onEnded { _ in model.endTouch() }
                )
                // The largest thing on the screen, and without this it is
                // an unnamed rectangle. Painting is a drag, which VoiceOver
                // does not have — so the hint says what it is for rather
                // than pretending it can be operated.
                //
                // Before the overlay, not after: collapsing the field into
                // one element after it would take the mixer's chips with it.
                .accessibilityElement()
                .accessibilityLabel(model.showingMixer ? "Tracks" : "Note field")
                .accessibilityHint(
                    model.showingMixer
                        ? "Double-tap a panel to open that track."
                        : "Drag to draw notes. Use Shuffle below to fill it.")
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .topLeading) { chips }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // --------------------------------------------------------------- mixer --

    /// The name and mute chips, one pair per panel, pinned inside the panel
    /// over its last rows of dots.
    ///
    /// They fade on their own 0.18-second curve rather than travelling with
    /// the panels, which is what the web's CSS transition does — the field
    /// flies, the controls simply arrive.
    private var chips: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<SequencerState.trackCount, id: \.self) { index in
                // The strip is worked out from the stage's size, which is
                // not known until the first frame has been drawn.
                let strip = model.chipStrip(index)
                if model.hasPart(index) && strip.width > 0 {
                    chipRow(index, height: strip.height)
                        .frame(width: strip.width, height: strip.height, alignment: .leading)
                        .offset(x: strip.minX, y: strip.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.showingMixer ? 1 : 0)
        .allowsHitTesting(model.showingMixer)
        .animation(.easeInOut(duration: 0.18), value: model.showingMixer)
    }

    private func chipRow(_ index: Int, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button {
                Haptics.toggle()
                model.openTrack(index)
            } label: {
                Text(model.voiceLabel(index))
                    // The chip sets its tracking to zero, unlike the labels.
                    .manrope(.regular, 16, tracking: 0)
                    .foregroundStyle(palette.background)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: height)
                    .background(palette.label)
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
                            ? palette.background : palette.label
                    )
                    .frame(width: height, height: height)
                    .background(
                        model.isMuted(index)
                            ? palette.label : palette.label.opacity(0.1)
                    )
            }
            .buttonStyle(PressFade())
            .accessibilityLabel(model.isMuted(index) ? "Unmute" : "Mute")
            .accessibilityAddTraits(model.isMuted(index) ? [.isSelected] : [])
        }
    }

    // -------------------------------------------------------------- footer --

    /// The tools belong to a track, so they go while the mixer is open —
    /// and the tile that leaves the mixer takes their place, across the same
    /// band, as the mockup has it.
    private var footer: some View {
        toolbar
            .opacity(model.showingMixer ? 0 : 1)
            .disabled(model.showingMixer)
            .overlay { backTile }
            .animation(.easeInOut(duration: 0.18), value: model.showingMixer)
    }

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
        .opacity(model.showingMixer ? 1 : 0)
        .disabled(!model.showingMixer)
        .allowsHitTesting(model.showingMixer)
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

#Preview {
    SequencerView(model: SequencerModel(store: InMemoryProjectStore()), onLeave: {})
}
