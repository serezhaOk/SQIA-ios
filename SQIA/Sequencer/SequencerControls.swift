// The sequencer's controls, from the Figma.
//
// Everything raised on this screen is the same object at heart: a shape a
// shade off the ground, a hairline, and a glow along the inside of its bottom
// edge. What changes between a pill and a button, and between resting and
// lit, is the colour of that glow and whether the shape is filled at all.
// So they are one set of parts rather than five views that happen to look
// alike, and a new state is a colour rather than a new control.

import SwiftUI

/// The radius every control on this screen is cut with. Larger than any of
/// them is tall, so each one comes out a capsule and they all agree.
private let controlRadius: CGFloat = 34

private func controlShape() -> RoundedRectangle {
    RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
}

extension View {
    /// The design's `inset 0 -2px 7.3px`, which SwiftUI has no shadow for.
    ///
    /// A stroke pushed up by two points and blurred, then clipped back
    /// inside the shape: what is left is a glow gathered along the bottom
    /// inside edge, which is what an inset shadow with a negative y is.
    func innerBloom(_ color: Color, blur: CGFloat = 7.3) -> some View {
        overlay {
            controlShape()
                .stroke(color, lineWidth: blur * 0.6)
                .blur(radius: blur / 2)
                .offset(y: -2)
                .mask { controlShape() }
                .allowsHitTesting(false)
        }
    }
}

/// A raised, filled control: the tempo, the key, the sound.
struct ControlPill<Label: View>: View {
    var width: CGFloat?
    var height: CGFloat = 40
    /// Nil takes the ground's own glow, which is what every pill wants.
    var bloom: Color?
    @ViewBuilder var label: () -> Label

    @Environment(\.sequencerPalette) private var palette

    var body: some View {
        label()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: width, height: height)
            .background(palette.surface, in: controlShape())
            .overlay { controlShape().strokeBorder(palette.hairline, lineWidth: 1) }
            .innerBloom(bloom ?? palette.bloom)
    }
}

/// How an icon button lights up.
///
/// Two colours rather than one, because the two buttons mean different
/// things by lighting. The eraser stays lit for as long as it is on — it is
/// a mode, and the screen has to keep saying so. The shuffle is lit only
/// while it is held, because it is an action and there is nothing to keep
/// saying afterwards.
struct BloomButtonStyle: ButtonStyle {
    /// Shown while `isOn`. Nil for a control with no on state.
    var onColor: Color?
    /// Shown while a finger is down.
    var pressColor: Color?
    var isOn: Bool = false
    /// Nil takes the ground's own label colour.
    var tint: Color?

    // A style is not a view and cannot read the environment, so what it
    // makes is one — which is the only way the ground reaches a control that
    // is styled rather than built. Not called `Body`: that is the protocol's
    // own associated type, and a private one would not be allowed to stand
    // for it.
    func makeBody(configuration: Configuration) -> some View {
        Chrome(
            configuration: configuration,
            onColor: onColor,
            pressColor: pressColor,
            isOn: isOn,
            tint: tint)
    }

    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let onColor: Color?
        let pressColor: Color?
        let isOn: Bool
        let tint: Color?

        @Environment(\.sequencerPalette) private var palette

        var body: some View {
            let lit: Color? = configuration.isPressed ? pressColor : (isOn ? onColor : nil)

            return configuration.label
                .foregroundStyle(tint ?? palette.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 20)
                .background { if lit != nil { controlShape().fill(palette.surface) } }
                .overlay {
                    controlShape().strokeBorder(
                        lit == nil ? palette.outline : palette.hairline,
                        lineWidth: 1)
                }
                .innerBloom(lit ?? .clear)
                // The design draws the shuffle two points larger while it is
                // held. Growing the control says the same thing and does not
                // shift what sits beside it.
                .scaleEffect(configuration.isPressed ? 1.03 : 1)
                .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: isOn)
                // On the way down, not on the way up: a press that reports
                // itself when the finger lifts feels like a lag rather than a
                // button.
                //
                // `body` carries no isolation of its own, and a hop to the
                // main actor would put the buzz a frame behind the finger —
                // which is the one thing haptics cannot afford. SwiftUI only
                // ever builds this on the main thread, so say so, the same
                // way the renderer does for its frame callback.
                .onChange(of: configuration.isPressed) { _, pressed in
                    guard pressed else { return }
                    MainActor.assumeIsolated { Haptics.tap() }
                }
        }
    }
}

/// The 24-point glyph both icon buttons carry, from the design's export.
struct ControlIcon: View {
    let name: String

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
}
