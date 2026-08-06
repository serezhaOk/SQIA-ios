// The app shell, and for now a standing check that the pieces underneath it
// are real: the bundled fonts resolve, the palette is right, and SQIACore —
// the pitch mapping, the note matrix and the dome geometry, all of it tested
// against fixtures taken from the web app — is linked and working.
//
// The field below is drawn with the actual `Field` geometry, so the dome can
// be judged on a device before the Metal renderer exists. It is a still
// image: no transport, no audio, no touch. Those arrive with the sequencer,
// and this view goes away when they do.

import SQIACore
import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            FieldPreview(pattern: Self.demoPattern)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 10) {
            SQIALogo().frame(width: 96, height: 96)
            Text("SQIA")
                .manrope(.bold, TextStyle.wordmarkSize, tracking: -0.02)
                .foregroundStyle(Palette.ui)
            Text("Built for sound accidents")
                .manrope(.regular, TextStyle.taglineSize)
                .foregroundStyle(Palette.tagline)
        }
        .padding(.top, 24)
    }

    private var footer: some View {
        Text("\(NoteGrid.columns) × \(NoteGrid.rows) · \(Music.scales.count) scales")
            .manrope(.medium, TextStyle.labelSize, tracking: TextStyle.labelTracking)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, 18)
    }

    /// A fixed pattern, so the preview looks the same every launch and any
    /// change to the geometry is obvious.
    private static let demoPattern: NoteGrid = {
        var grid = NoteGrid()
        grid.randomize(using: Mulberry32(seed: 12345))
        return grid
    }()
}

/// The dot field, drawn flat: every cell centre pushed over the dome, sized
/// by the local lens scale and lit by its intensity. The live version adds
/// flash energy, colour ripples and the neighbour push — that belongs to the
/// Metal renderer.
private struct FieldPreview: View {
    let pattern: NoteGrid

    var body: some View {
        Canvas { context, size in
            let layout = Field.layout(x: 0, y: 0, width: size.width, height: size.height)
            let baseDot = max(1.6, layout.cell * 0.075)

            for row in 0..<NoteGrid.rows {
                for column in 0..<NoteGrid.columns {
                    let x = layout.ox + (Double(column) + 0.5) * layout.cell
                    let y = layout.oy + (Double(row) + 0.5) * layout.cell
                    let point = Field.warp(x: x, y: y, in: layout)
                    let lens = Field.warpScale(x: x, y: y, in: layout)

                    let intensity = Double(pattern.at(row: row, column: column))
                    let radius = (baseDot + intensity * layout.cell * 0.2) * lens
                    let alpha = intensity > 0 ? min(1, 0.4 + 0.45 * intensity) : 0.2

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
