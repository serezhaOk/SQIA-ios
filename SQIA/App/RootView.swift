// The app shell, and for now a bench for what is underneath it: the bundled
// fonts and palette, the field drawn on Metal from SQIACore's geometry and
// animation, and the real engine playing a real pattern through it.
//
// The sequencer screen replaces all of this. Until then, this is what the
// audio and field milestones are judged on: press play and watch the notes
// bloom exactly as they sound, leave it running for ten minutes, take a
// call, plug in headphones.

import SQIACore
import SwiftUI

struct RootView: View {
    @State private var probe = AudioProbe()

    var body: some View {
        VStack(spacing: 0) {
            header
            FieldView { rect in [probe.scene.layer(in: rect)] }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bench
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 8) {
            SQIALogo().frame(width: 64, height: 64)
            Text("SQIA")
                .manrope(.bold, 28, tracking: -0.02)
                .foregroundStyle(Palette.ui)
        }
        .padding(.top, 12)
    }

    private var bench: some View {
        VStack(spacing: 14) {
            HStack(spacing: 28) {
                Button(String(format: "%.0f BPM", probe.bpm)) {
                    probe.bumpTempo()
                }
                .manrope(.medium, TextStyle.labelSize, tracking: TextStyle.labelTracking)
                .foregroundStyle(Palette.ink)

                Button(probe.isPlaying ? "STOP" : "PLAY") {
                    probe.toggle()
                }
                .manrope(.semibold, TextStyle.labelSize, tracking: TextStyle.labelTracking)
                .foregroundStyle(probe.isPlaying ? Palette.accent : Palette.ink)
            }

            Text(readout)
                .manrope(.regular, 11.5)
                .foregroundStyle(Palette.copyright)
        }
        .padding(.bottom, 18)
    }

    private var readout: String {
        var parts = [probe.status, "\(NoteGrid.columns)×\(NoteGrid.rows)"]
        if probe.stepsPlayed > 0 { parts.append("\(probe.stepsPlayed) steps") }
        if probe.droppedNotes > 0 { parts.append("\(probe.droppedNotes) dropped") }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    RootView()
}
