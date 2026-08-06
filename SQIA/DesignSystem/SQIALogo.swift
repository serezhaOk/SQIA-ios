// The mark: a note field fading into the distance, inside a rounded square.
//
// Geometry copied from the web app's index.html, on its 120x120 viewBox, so
// the two stay identical at any size.

import SwiftUI

struct SQIALogo: View {
    /// cx, cy, r, shade
    private static let dots: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
        (30, 32, 7, 0xD9D9D9), (53, 32, 7, 0xD9D9D9),
        (75, 32, 3, 0xD9D9D9), (96, 32, 7, 0xD9D9D9),
        (32, 56, 4, 0xD9D9D9), (54, 56, 4, 0xD9D9D9),
        (75, 56, 2.4, 0x8A8A8A), (94, 56, 2.4, 0x8A8A8A),
        (34, 76, 2.4, 0x7A7A7A), (55, 76, 2.4, 0x7A7A7A),
        (75, 76, 2.4, 0x6D6D6D), (92, 76, 2.4, 0x6D6D6D),
        (36, 93, 1.8, 0x5C5C5C), (56, 93, 1.8, 0x5C5C5C),
        (75, 93, 1.8, 0x5C5C5C), (90, 93, 1.8, 0x5C5C5C),
    ]

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 120

            let border = CGRect(x: 1 * s, y: 1 * s, width: 118 * s, height: 118 * s)
            context.stroke(
                Path(roundedRect: border, cornerRadius: 26 * s),
                with: .color(Palette.logoStroke),
                lineWidth: 2 * s
            )

            for (cx, cy, r, shade) in Self.dots {
                let rect = CGRect(
                    x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s)
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: shade)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The compact mark in the projects header: four dots, each dimmer and
/// smaller than the last.
struct SQIAMiniLogo: View {
    /// diameter, opacity — matching `.p-logo i` in the CSS.
    private static let dots: [(CGFloat, Double)] = [(12, 1), (7, 0.75), (7, 0.55), (5, 0.4)]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                dot(0)
                dot(1)
            }
            GridRow {
                dot(2)
                dot(3)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private func dot(_ index: Int) -> some View {
        let (size, opacity) = Self.dots[index]
        return Circle()
            .fill(Palette.ui.opacity(opacity))
            .frame(width: size, height: size)
            .frame(width: 20, height: 20)
    }
}

#Preview {
    VStack(spacing: 40) {
        SQIALogo().frame(width: 132, height: 132)
        SQIAMiniLogo()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.background)
}
