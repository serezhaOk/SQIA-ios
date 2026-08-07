// The app shell, and for now a bench for what is underneath it: the bundled
// fonts and palette, SQIACore's geometry drawing the field, and — since the
// audio foundation landed — the real engine playing a real pattern.
//
// The sequencer screen replaces all of this. Until then, this is what the
// audio milestone is judged on: press play, leave it running for ten
// minutes, take a call, plug in headphones, and listen for a tempo that
// never drifts.

import SQIACore
import SwiftUI

struct RootView: View {
    @State private var probe = AudioProbe()

    var body: some View {
        VStack(spacing: 0) {
            header
            FieldPreview(pattern: probe.pattern, playhead: probe.playhead)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bench
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 10) {
            SQIALogo().frame(width: 76, height: 76)
            Text("SQIA")
                .manrope(.bold, 32, tracking: -0.02)
                .foregroundStyle(Palette.ui)
            Text("Built for sound accidents")
                .manrope(.regular, TextStyle.taglineSize)
                .foregroundStyle(Palette.tagline)
        }
        .padding(.top, 16)
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

/// The dot field, drawn flat: every cell centre pushed over the dome, sized
/// by the local lens scale and lit by its intensity, with the sounding row
/// brighter. The live version adds flash energy, colour ripples and the
/// neighbour push — that belongs to the Metal renderer.
private struct FieldPreview: View {
    let pattern: NoteGrid
    let playhead: Int

    var body: some View {
        Canvas { context, size in
            let layout = Field.layout(x: 0, y: 0, width: size.width, height: size.height)
            let baseDot = max(1.6, layout.cell * 0.075)

            for row in 0..<NoteGrid.rows {
                let onHead = row == playhead
                for column in 0..<NoteGrid.columns {
                    let x = layout.ox + (Double(column) + 0.5) * layout.cell
                    let y = layout.oy + (Double(row) + 0.5) * layout.cell
                    let point = Field.warp(x: x, y: y, in: layout)
                    let lens = Field.warpScale(x: x, y: y, in: layout)

                    let intensity = Double(pattern.at(row: row, column: column))
                    let radius = (baseDot + intensity * layout.cell * 0.2) * lens
                    let alpha =
                        intensity > 0
                        ? min(1, 0.4 + 0.45 * intensity + (onHead ? 0.3 : 0))
                        : (onHead ? 0.5 : 0.2)

                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }
            }
        }
        .drawingGroup()
    }
}

#Preview {
    RootView()
}
