// A knob for one of the mixer's effects, 0 to 100.
//
// A first pass from the Figma, there to hear the effects by: a disc with a
// dotted rim and a line that says where it is. Drag up to turn it up, down
// to turn it down — sideways counts as well, so a thumb moving on a
// diagonal still gets somewhere. Double tap goes back to zero.
//
// At zero the line points straight down, as drawn, and it turns clockwise
// from there: all the way up is most of a turn round, just short of where
// it started.

import SQIACore
import SwiftUI

struct EffectKnob: View {
    let title: String
    /// 0…1.
    let value: Double
    var onChange: (Double) -> Void

    /// How far a finger travels for the whole range.
    private static let travel: CGFloat = 220
    /// How far round the line goes between 0 and 100.
    private static let sweep = 300.0

    @State private var dragStart: Double?
    @Environment(\.sequencerPalette) private var palette

    private var percent: Int { Int((value * 100).rounded()) }

    var body: some View {
        VStack(spacing: 10) {
            // The number while it is being turned, so it can be read off by
            // ear-testing; the name the rest of the time.
            Text(dragStart == nil ? title : "\(percent)")
                .manrope(.regular, 14, tracking: 0)
                .foregroundStyle(palette.label.opacity(0.5))
                .monospacedDigit()
                .frame(height: 18)

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                dial(size: size)
                    .frame(width: size, height: size)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            // A little narrower than the panel above, and clear of the next
            // row's name.
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .contentShape(Rectangle())
        .gesture(drag)
        .onTapGesture(count: 2) {
            guard value != 0 else { return }
            Haptics.tap()
            onChange(0)
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue("\(percent)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, value + 0.05))
            case .decrement: onChange(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }

    private func dial(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x3A3A3A))
            Circle()
                .strokeBorder(
                    palette.label.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [1, 2.5]))
            // The line from the middle toward the rim, drawn pointing down
            // and turned into place.
            Capsule()
                .fill(Color.black)
                .frame(width: 4, height: size * 0.38)
                .offset(y: size * 0.26)
                .rotationEffect(.degrees(value * Self.sweep))
        }
        .animation(.interactiveSpring(response: 0.12), value: value)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                if dragStart == nil {
                    dragStart = value
                    Haptics.warm()
                }
                guard let start = dragStart else { return }
                let moved = gesture.translation.width - gesture.translation.height
                let next = min(max(start + Double(moved / Self.travel), 0), 1)
                let before = Int((value * 100).rounded())
                let after = Int((next * 100).rounded())
                // A click every ten, and at either end.
                if before / 10 != after / 10 || (after != before && (after == 0 || after == 100)) {
                    Haptics.step()
                }
                onChange(next)
            }
            .onEnded { _ in dragStart = nil }
    }
}

#Preview {
    EffectKnob(title: "Reverb", value: 0.3, onChange: { _ in })
        .frame(width: 160, height: 190)
        .padding()
        .background(Color(hex: 0x1C1C1C))
}
