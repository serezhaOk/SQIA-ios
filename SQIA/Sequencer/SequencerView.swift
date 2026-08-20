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
        .overlay(alignment: .top) {
            #if DEBUG
                // What the audio thread costs, in a Run build only. Under
                // about 0.2× there is room to spare; approaching 1.0× is a
                // crackle waiting for the phone to get busy.
                Text(model.renderLoad)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.ink.opacity(0.35))
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            #endif
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
            HStack(spacing: 10) {
                label(model.state.rootName) { model.cycleRoot() }
                label(model.state.scale.name.uppercased()) { model.cycleScale() }
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

    /// One dot per track, the active one bright. In the web this opens the
    /// mixer; until that exists it steps between the tracks.
    private var trackDots: some View {
        Button {
            model.cycleTrack()
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
    }

    // --------------------------------------------------------------- stage --

    private var stage: some View {
        GeometryReader { geometry in
            FieldView { rect in model.layers(in: rect) }
                .contentShape(Rectangle())
                .gesture(
                    // No minimum distance, so a tap paints as surely as a
                    // drag does.
                    DragGesture(minimumDistance: 0)
                        .onChanged { model.touch(at: $0.location) }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // -------------------------------------------------------------- footer --

    private var footer: some View {
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
