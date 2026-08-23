// The tempo, opened out.
//
// A tap on the tempo used to bump it ten and wrap at two hundred, which is
// how the web does it — and reaching a tempo by tapping upward eleven times
// is a web gesture, not a phone one. So a tap opens this instead: a rule you
// drag under a fixed marker, one notch per beat, with the engine ticking
// under your finger so the count can be felt rather than read.
//
// Dragging the label itself still scrubs, as it always did. This is the way
// in for anyone who does not know that.

import SQIACore
import SwiftUI

struct TempoWheel: View {
    let bpm: Double
    let onChange: (Double) -> Void

    /// Points per beat along the rule. Wide enough that a beat is a
    /// deliberate movement rather than something a thumb crosses by
    /// accident, narrow enough to see thirty of them at once.
    private static let spacing: CGFloat = 9
    private static let ruleWidth: CGFloat = 334
    private static let ruleHeight: CGFloat = 13

    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            Text("Set tempo")
                .manrope(.medium, 15)
                .foregroundStyle(Palette.Sequencer.label)
                .padding(.top, 42)

            rule
                .padding(.top, 38)

            Text("\(Int(bpm.rounded())) bpm")
                .manrope(.bold, 20, tracking: -0.02)
                .foregroundStyle(Palette.Sequencer.label)
                .monospacedDigit()
                .padding(.top, 27)

            Spacer(minLength: 0)
        }
        .frame(width: 355, height: 184)
        .background(Palette.Sequencer.surface, in: card)
        .overlay { card.strokeBorder(Color.black, lineWidth: 1) }
        // The card's glow is the controls' glow, further out — it is a
        // bigger object and the design opens the shadow up to match.
        .innerBloom(Palette.Sequencer.bloom, blur: 14.3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(Int(bpm.rounded())) beats per minute")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(Tempo.clamp(bpm + 5))
            case .decrement: onChange(Tempo.clamp(bpm - 5))
            @unknown default: break
            }
        }
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
    }

    // ---------------------------------------------------------------- rule --

    private var rule: some View {
        Canvas { context, size in
            let middle = size.width / 2
            // Only the beats that can be seen, worked out from the middle
            // rather than drawn from forty and clipped.
            let reach = Int(size.width / Self.spacing / 2) + 2
            let nearest = bpm.rounded()

            for step in -reach...reach {
                let beat = nearest + Double(step)
                guard beat >= Tempo.minimum, beat <= Tempo.maximum else { continue }
                let x = middle + CGFloat(beat - bpm) * Self.spacing
                guard x >= 0, x <= size.width else { continue }

                // The rule fades at both ends rather than being cut off, so
                // it reads as continuing past the card.
                let fade = 1 - min(1, abs(x - middle) / middle)
                let tall = beat.truncatingRemainder(dividingBy: 10) == 0
                let height = tall ? size.height : size.height * 0.55

                context.fill(
                    Path(
                        CGRect(
                            x: x - 0.75, y: (size.height - height) / 2,
                            width: 1.5, height: height)),
                    with: .color(Palette.Sequencer.label.opacity(0.18 + 0.5 * fade)))
            }

            // The marker, and the only thing on the rule that does not move.
            context.fill(
                Path(CGRect(x: middle - 1.25, y: 0, width: 2.5, height: size.height)),
                with: .color(Palette.Sequencer.label))
        }
        .frame(width: Self.ruleWidth, height: Self.ruleHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = bpm
                        Haptics.warm()
                    }
                    guard let start = dragStart else { return }
                    // The rule travels with the finger, so what sits under
                    // the marker goes the other way.
                    let moved = start - Double(value.translation.width) / Double(Self.spacing)
                    let next = Tempo.clamp(moved)
                    if Int(next.rounded()) != Int(bpm.rounded()) { Haptics.step() }
                    onChange(next)
                }
                .onEnded { _ in
                    dragStart = nil
                    onChange(Tempo.clamp(bpm.rounded()))
                }
        )
    }
}

/// The card, the scrim behind it, and the way out.
struct TempoWheelOverlay: View {
    let bpm: Double
    let onChange: (Double) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // Anywhere off the card closes it. No visible scrim: the design
            // leaves the field showing, and the card is legible over it.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    onClose()
                }

            TempoWheel(bpm: bpm, onChange: onChange)
                .padding(.top, 10)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
