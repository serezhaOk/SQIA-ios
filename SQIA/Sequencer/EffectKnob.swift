// A knob for one of the mixer's effects, 0 to 100.
//
// From the Figma: a grey disc with a notched rim, forty notches round it,
// and a dark line from just below the middle out toward the rim that says
// where it is. Drag up to turn it up, down to turn it down — sideways counts
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

    private var dial: some View {
        let size = Self.dialSize
        return ZStack {
            NotchedDisc()
                .fill(Color(hex: 0x6D6D6D))
            // From 9.75 below the middle to 48.4 below it, as drawn, and
            // turned into place round the middle.
            Capsule()
                .fill(Color(hex: 0x1C1C1C))
                .frame(width: 3, height: 38.6 + 3)
                .offset(y: 9.75 + 38.6 / 2)
                .rotationEffect(.degrees(value * Self.sweep))
        }
        .frame(width: size, height: size)
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

/// The dial's outline: a circle with forty shallow notches round its rim,
/// one of them dead centre at the top, as in the design's export.
///
/// Worked out as a radius that dips two points for most of each fortieth
/// and eases out again, rather than copied from the export's path, so it
/// stays true at any size.
private struct NotchedDisc: Shape {
    var notches = 40
    /// Two points on the design's 109.5-point dial.
    var depth: CGFloat = 2 / 109.5
    /// How much of each period is notch.
    var notchShare = 0.62

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let dip = depth * radius * 2
        let steps = notches * 24
        var path = Path()
        for i in 0...steps {
            let turn = Double(i) / Double(steps)
            // Zero at the top, where a notch is centred.
            let phase = (turn * Double(notches) + 0.5).truncatingRemainder(dividingBy: 1)
            let nearness = 1 - abs(phase - 0.5) * 2  // 1 at a notch's middle
            let t = min(max((nearness - (1 - notchShare)) / 0.12, 0), 1)
            let inward = t * t * (3 - 2 * t)
            let r = radius - dip * CGFloat(inward)
            let angle = turn * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
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
