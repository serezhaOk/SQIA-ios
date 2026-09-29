// A knob for one of the mixer's effects, 0 to 100.
//
// From the Figma: a grey disc with forty bites out of its rim and a dark
// line from just below the middle out toward the edge — the design's own
// export, turned whole the way a real knob turns. Drag up to turn it up, down to turn it down — sideways counts
// as well, so a thumb moving on a diagonal still gets somewhere. Double tap
// goes back to zero.
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

    /// The design's dial, 109.5 across, in a 120-wide slot.
    static let dialSize: CGFloat = 109.5
    static let slotWidth: CGFloat = 120
    /// Dial, gap, label.
    static let height: CGFloat = dialSize + 12 + 18

    /// How far a finger travels for the whole range.
    private static let travel: CGFloat = 220
    /// How far round the line goes between 0 and 100.
    private static let sweep = 300.0

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

    /// The disc is centred in its 120 by 109.5 frame, so turning the frame
    /// about its middle turns the disc about its own.
    private var dial: some View {
        Image("KnobDial")
            .resizable()
            .frame(width: Self.slotWidth, height: Self.dialSize)
            .rotationEffect(.degrees(value * Self.sweep))
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
    HStack(spacing: 0) {
        EffectKnob(title: "Scatter", value: 0, onChange: { _ in })
        EffectKnob(title: "Delay", value: 0.3, onChange: { _ in })
    }
    .padding()
    .background(Color(hex: 0x1C1C1C))
}
