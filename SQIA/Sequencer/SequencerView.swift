// The sequencer screen.
//
// Tempo and key across the top, the field in the middle, the eraser, the
// sound and the randomiser along the bottom. Metrics are the web app's, from
// style.css: 18 by 20 points of padding on both bars, labels at 0.82rem with
// wide tracking, nine-point track dots.

import SQIACore
import SwiftUI

struct SequencerView: View {
    @State private var model = SequencerModel()
    @State private var showingVoices = false
    @State private var showingKey = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            footer
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(isPresented: $showingVoices) {
            VoiceSheet(
                selected: model.state.activeTrack.voiceIndex,
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
        .onAppear { model.start() }
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
    }

    // -------------------------------------------------------------- header --

    private var header: some View {
        HStack(spacing: 0) {
            tempoLabel
            Spacer(minLength: 8)
            trackDots
            Spacer(minLength: 8)
            // One tap opens the key rather than stepping it: reaching the
            // twelfth note by tapping eleven times is a web gesture, not a
            // phone one.
            HStack(spacing: 10) {
                label(model.state.rootName) { showingKey = true }
                label(model.state.scale.name.uppercased()) { showingKey = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    /// Drag sideways to scrub the tempo, tap to bump it.
    private var tempoLabel: some View {
        Text("\(Int(model.state.bpm)) BPM")
            .manrope(.regular, TextStyle.labelSize, tracking: TextStyle.labelTracking)
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { model.scrubTempo(dx: $0.translation.width) }
                    .onEnded { _ in model.endTempoDrag() }
            )
            .accessibilityLabel("Tempo")
            .accessibilityValue("\(Int(model.state.bpm)) beats per minute")
    }

    /// One dot per track, the active one bright. Tapping opens the mixer,
    /// as in the web — and the control goes away while it is open, because
    /// there is nothing left for it to do.
    private var trackDots: some View {
        Button {
            model.openMixer()
        } label: {
            HStack(spacing: 7) {
                ForEach(0..<SequencerState.trackCount, id: \.self) { index in
                    Circle()
                        .fill(Palette.ui)
                        .opacity(index == model.state.activeTrackIndex ? 1 : 0.3)
                        .frame(width: 9, height: 9)
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
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .topLeading) { chips }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { meter }
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
                model.openTrack(index)
            } label: {
                Text(model.voiceLabel(index))
                    // The chip sets its tracking to zero, unlike the labels.
                    .manrope(.regular, 16, tracking: 0)
                    .foregroundStyle(Palette.background)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: height)
                    .background(Palette.ui)
            }
            .buttonStyle(PressFade())
            .accessibilityLabel("Open \(model.voiceLabel(index))")

            Spacer(minLength: 4)

            Button {
                model.toggleMute(index)
            } label: {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(model.isMuted(index) ? Palette.background : Palette.ui)
                    .frame(width: height, height: height)
                    .background(
                        model.isMuted(index) ? Palette.ui : Palette.ui.opacity(0.1)
                    )
            }
            .buttonStyle(PressFade())
            .accessibilityLabel(model.isMuted(index) ? "Unmute" : "Mute")
            .accessibilityAddTraits(model.isMuted(index) ? [.isSelected] : [])
        }
    }

    /// Where the time goes, in a Run build only. AUD is the audio thread's
    /// share of realtime — under 0.2× there is room to spare, near 1.0× and
    /// nothing can help. UI is what one frame costs the main thread, which
    /// the audio thread has to share a phone with.
    @ViewBuilder
    private var meter: some View {
        #if DEBUG
            Text(model.renderLoad)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Palette.background)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Palette.ink.opacity(0.9), in: Capsule())
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
        #endif
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
            // At M7 this flushes the autosave and returns to the library.
            // Until there is a library, leaving the mixer is the whole of
            // what it can honestly do.
            model.openTrack(model.state.activeTrackIndex)
        } label: {
            Text("Back to projects")
                // 0.15px at 15px, which is a hundredth of an em.
                .manrope(.semibold, 15, tracking: 0.01)
                .foregroundStyle(Palette.ui)
                .frame(maxWidth: 335)
                .frame(height: 126)
                .background(Palette.ui.opacity(0.2), in: RoundedRectangle(cornerRadius: 32))
        }
        .buttonStyle(PressFade())
        .opacity(model.showingMixer ? 1 : 0)
        .disabled(!model.showingMixer)
        .allowsHitTesting(model.showingMixer)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            label("ERASE", active: model.eraseMode) { model.toggleErase() }
            Spacer(minLength: 8)
            Text(model.activeVoiceLabel)
                .manrope(
                    .regular, TextStyle.labelSize, tracking: TextStyle.voiceLabelTracking
                )
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { showingVoices = true }
                .accessibilityLabel("Sound")
                .accessibilityValue(model.activeVoiceLabel)
            Spacer(minLength: 8)
            label("RNDM") { model.randomize() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // ------------------------------------------------------------ the label --

    private func label(
        _ text: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .manrope(.regular, TextStyle.labelSize, tracking: TextStyle.labelTracking)
                .foregroundStyle(active ? Palette.accent : Palette.ink)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
        }
        .buttonStyle(PressFade())
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
    SequencerView()
}
