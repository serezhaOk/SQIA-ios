// A knob for one of the mixer's effects, 0 to 100.
//
// From the Figma: a grey disc in a heavy black ring, and a black dot inside
// the rim that says where it is set. Drag up to turn it up, down to turn it
// down — sideways counts as well, so a thumb moving on a diagonal still gets
// somewhere. Double tap goes back to zero.
//
// At zero the dot sits at about seven o'clock, where the design draws
// Scatter, and it turns clockwise from there over the top to five o'clock —
// the dead zone at the bottom, the way a knob on a desk has one.

import SQIACore
import SwiftUI

struct EffectKnob: View {
    let title: String
    /// 0…1.
    let value: Double
    var onChange: (Double) -> Void

    /// The design's dial, 109.5 across, in a 120-wide slot.
    static let dialSize: CGFloat = 109.5
    static let slotWidth: CGFloat = 120
    /// Dial, gap, label.
    static let height: CGFloat = dialSize + 12 + 18

    /// The disc as drawn: 55 to the middle of a 5-point ring, so 115
    /// across its outside — a little over the slot's height, as in the
    /// design, where it hangs over the frame it is laid out in.
    private static let discSize: CGFloat = 115
    private static let ringWidth: CGFloat = 5
    private static let dotSize: CGFloat = 10
    /// From the disc's middle to the dot's.
    private static let dotRadius: CGFloat = 39.5

    /// How far a finger travels for the whole range.
    private static let travel: CGFloat = 220
    /// Where the dot is at zero, clockwise from twelve o'clock, and how far
    /// round it goes to 100 — symmetric about six o'clock.
    private static let rest = 215.0
    private static let sweep = 290.0

    @State private var dragStart: Double?

    private var percent: Int { Int((value * 100).rounded()) }

    var body: some View {
        VStack(spacing: 12) {
            dial
                .frame(width: Self.slotWidth, height: Self.dialSize)

            // Under the dial, where a thumb turning it does not cover it.
            // The number while it is being turned, so it can be read off by
            // ear-testing; the name the rest of the time.
            Text(dragStart == nil ? title : "\(percent)")
                .manrope(.regular, 13, tracking: 0.02)
                .foregroundStyle(Color(hex: 0xF5F3F3))
                .monospacedDigit()
                .frame(height: 18)
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

    /// The disc stays put and the dot goes round it: turning the whole of a
    /// plain disc would look the same as not turning it.
    private var dial: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xB9B9B9))
                .overlay { Circle().strokeBorder(.black, lineWidth: Self.ringWidth) }
                .frame(width: Self.discSize, height: Self.discSize)

            Circle()
                .fill(.black)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .offset(y: -Self.dotRadius)
                .rotationEffect(.degrees(Self.rest + value * Self.sweep))
                .animation(.interactiveSpring(response: 0.12), value: value)
        }
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
    HStack(spacing: 0) {
        EffectKnob(title: "Scatter", value: 0, onChange: { _ in })
        EffectKnob(title: "Delay", value: 0.3, onChange: { _ in })
    }
    .padding()
    .background(Color(hex: 0x1C1C1C))
}
