// The workbench for the field's look.
//
// It replaces the synth panel in the menu, and it is the same argument in a
// different place: a sound cannot be judged from its source, and neither can
// a colour, a decay or a taper. Everything here is bound live — the field
// behind the sheet is redrawing as the slider moves, which is the only way
// any of it can be decided.
//
// Debug builds only. What it produces is written back into
// `FieldTuning.current`; the panel itself does not ship.

#if DEBUG

import SQIACore
import SwiftUI
import UIKit

struct FieldTuningView: View {
    let model: SequencerModel
    @State private var copied = false

    var body: some View {
        List {
            Section {
                slider("Dots", \.dotScale, 0.1...2)
                slider("Blobs", \.blobScale, 0.3...2.5)
            } header: {
                Text("Size")
            } footer: {
                Text(
                    """
                    The resting grid, and how far a drawn note reaches. \
                    Blobs below about 0.7 stop overlapping their neighbours, \
                    and a stroke comes apart into separate circles instead \
                    of closing into one shape.
                    """)
            }

            Section {
                slider("At the rim", \.rimScale, 0.2...1.2)
                slider("Added in the middle", \.centreLift, 0...1.2)
            } header: {
                Text("Taper")
            } footer: {
                Text(
                    "Both at one and nothing tapers: the grid reads as a weight "
                        + "sitting on the screen rather than a surface.")
            }

            Section {
                slider("Return", \.returnSeconds, 0.1...6, unit: "s")
                slider("Spread", \.spread, 0...2)
                slider("Ripple rings", \.rippleFrequency, 0...14)
                slider("Ripple speed", \.rippleSpeed, 0...8)
                slider("Ripple depth", \.rippleAmplitude, 0...0.6)
            } header: {
                Text("Motion")
            } footer: {
                Text(
                    """
                    How long a struck note takes to give its colour back, how \
                    much further it reaches while it is hot, and the ring \
                    travelling out of it. Depth at zero turns the ring off.
                    """)
            }

            Section {
                slider("Gain", \.gain, 0.02...1.2)
                slider("Edge", \.edge, 0.01...0.8)
            } header: {
                Text("Light")
            } footer: {
                Text(
                    """
                    Gain decides where cool ends and hot begins: a lone note \
                    sums to about one at its middle and a crowded corner to \
                    three or four. Edge is where the field dissolves into the \
                    ground.
                    """)
            }

            Section {
                Toggle(
                    "Light ground",
                    isOn: Binding(
                        get: { model.lightBackground },
                        set: { model.setLightBackground($0) }))
            } header: {
                Text("Ground")
            } footer: {
                Text(
                    """
                    Turns the whole screen over — the field's ground and the \
                    controls with it. The field's own colours are the ones \
                    below and do not turn: a look tuned against black is \
                    mostly pale, and pale on paper is nothing at all. Start \
                    with the resting grid and the drawn ramp.
                    """)
            }

            Section {
                hex("Resting grid", model.fieldTuning.hint) { colour in
                    write { $0.hint = colour }
                }
            } header: {
                Text("Grid")
            }

            ramp("Drawn", \.rest, count: FieldTuning.restStops)
            ramp("Sounding", \.heat, count: FieldTuning.heatStops)

            Section {
                Button {
                    UIPasteboard.general.string = model.fieldTuning.json
                    copied = true
                } label: {
                    Label(
                        copied ? "Copied" : "Copy as JSON",
                        systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button(role: .destructive) {
                    model.resetFieldTuning()
                    copied = false
                } label: {
                    Label("Back to the built-in look", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.fieldTuning.isDefault)
            } footer: {
                Text(
                    model.fieldTuning.isDefault
                        ? "The field is where it was last written down."
                        : "Moved from the look this build ships with. Copy it out "
                            + "and paste it into FieldTuning.current to keep it."
                )
            }
        }
        .navigationTitle("Field")
        .navigationBarTitleDisplayMode(.inline)
    }

    // --------------------------------------------------------------- parts --

    private func write(_ edit: (inout FieldTuning) -> Void) {
        var next = model.fieldTuning
        edit(&next)
        model.setFieldTuning(next)
        copied = false
    }

    private func slider(
        _ title: String,
        _ path: WritableKeyPath<FieldTuning, Double>,
        _ range: ClosedRange<Double>,
        unit: String = ""
    ) -> some View {
        let value = Binding(
            get: { model.fieldTuning[keyPath: path] },
            set: { new in write { $0[keyPath: path] = new } }
        )
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue) + unit)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    @ViewBuilder
    private func ramp(
        _ title: String,
        _ path: WritableKeyPath<FieldTuning, [ColorStop]>,
        count: Int
    ) -> some View {
        Section {
            ForEach(0..<count, id: \.self) { index in
                let stops = model.fieldTuning[keyPath: path]
                if index < stops.count {
                    VStack(alignment: .leading, spacing: 6) {
                        hex(place(stops[index].at), stops[index].color) { colour in
                            write { $0[keyPath: path][index].color = colour }
                        }
                        Slider(
                            value: Binding(
                                get: { model.fieldTuning[keyPath: path][index].at },
                                set: { new in write { $0[keyPath: path][index].at = new } }
                            ),
                            in: 0...1)
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(
                title == "Drawn"
                    ? "A note sitting on the field, low to high."
                    : "A note while it is sounding. The field crossfades to this "
                        + "one and back as the note decays.")
        }
    }

    private func place(_ at: Double) -> String {
        String(format: "%.0f%%", at * 100)
    }

    private func hex(
        _ title: String,
        _ colour: RGB,
        onChange: @escaping (RGB) -> Void
    ) -> some View {
        HexField(title: title, colour: colour, onChange: onChange)
    }
}

/// A colour typed rather than picked.
///
/// The text is held locally: binding it straight to the value would reject
/// every half-typed hex and fight the keyboard on the way to a valid one.
private struct HexField: View {
    let title: String
    let colour: RGB
    let onChange: (RGB) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(colour))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
                .frame(width: 30, height: 22)

            Text(title)
            Spacer(minLength: 8)

            TextField("RRGGBB", text: $text)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .frame(width: 96)
                .onChange(of: text) { _, typed in
                    guard let parsed = RGB(hex: typed), parsed != colour else { return }
                    onChange(parsed)
                }
        }
        .onAppear { text = colour.hex }
        // Reset and paste both change the colour from somewhere other than
        // this field, and the text has to follow.
        .onChange(of: colour) { _, now in
            if RGB(hex: text) != now { text = now.hex }
        }
    }
}

extension Color {
    init(_ rgb: RGB) {
        self.init(
            .sRGB, red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255)
    }
}

#endif
