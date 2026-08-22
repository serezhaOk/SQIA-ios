// The tuning panel: every number that shapes a voice, on a slider.
//
// Each preset rolls its values fresh per note out of a range, so most knobs
// are two handles rather than one — a low end and a high end. Drag them
// together and the preset becomes consistent; drag them apart and it wanders
// again. That is the whole idea the sound is built on, so the control has to
// show it rather than hide it behind a single number.
//
// Everything opens on the web's values. What has been moved is marked, and
// the whole set copies out as JSON, so a tuning arrived at by ear can be
// read back and written into the source.
//
// Debug builds only. It is the workbench the sound was made on, not a
// feature — twenty-nine sliders with no explanation is not something to hand
// somebody who opened a music app. What it produced ships as `Tuning.tuned`;
// this does not ship at all.

#if DEBUG

import SQIACore
import SwiftUI
import UIKit

struct TuningView: View {
    let model: SequencerModel
    @State private var copied = false

    var body: some View {
        List {
            ForEach(SynthPreset.allCases, id: \.rawValue) { preset in
                Section {
                    ForEach(Tuning.specs(for: preset), id: \.knob) { spec in
                        row(spec)
                    }
                } header: {
                    Text(preset.label)
                } footer: {
                    Text(preset.hint)
                }
            }

            Section {
                ForEach(Tuning.specs(for: nil), id: \.knob) { spec in
                    row(spec)
                }
            } header: {
                Text("Room")
            } footer: {
                Text(
                    """
                    The shared reverb. Its decay and damping are not the \
                    web's: that one convolves against seven seconds of white \
                    noise under an envelope, so its tail runs longer and \
                    stays bright, while this is a feedback network that \
                    darkens as it fades. Raise both to move towards it.
                    """)
            }
        }
        .navigationTitle("Tuning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    Button("Back to defaults") { model.resetAllTuning() }
                        .disabled(model.tuning.isDefault)
                    // The web is kept reachable as the reference it is: the
                    // way to hear what was moved away from is to hear it.
                    Button("Hear the web's numbers") { model.resetToWeb() }
                        .disabled(model.tuning.isWeb)
                } label: {
                    Text("Reset")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(copied ? "Copied" : "Copy") { copy() }
                    .disabled(model.tuning.isDefault)
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = model.tuning.json()
        copied = true
        // Long enough to read, short enough not to look stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    // ----------------------------------------------------------------- row --

    @ViewBuilder
    private func row(_ spec: TuningSpec) -> some View {
        let frame = model.tuning[spec.knob]
        let moved = frame != Tuning.tuned[spec.knob]

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(spec.label)
                    .font(.body)
                Spacer(minLength: 8)
                Text(reading(spec, frame))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(moved ? Color.accentColor : .secondary)
                if moved {
                    Button {
                        model.resetTuning(spec.knob)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset \(spec.label)")
                }
            }

            if spec.unit == .flag {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { frame.lower >= 0.5 },
                        set: { model.setTuning(spec.knob, to: TunableRange($0 ? 1 : 0)) })
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if spec.isSingle {
                handle(spec, frame.low) { model.setTuning(spec.knob, to: TunableRange($0)) }
            } else {
                // Neither handle may pass the other, or the reading would
                // say "2.0 – 0.5" and mean the same as "0.5 – 2.0".
                handle(spec, frame.low) {
                    model.setTuning(
                        spec.knob, to: TunableRange(min($0, frame.high), frame.high))
                }
                handle(spec, frame.high) {
                    model.setTuning(
                        spec.knob, to: TunableRange(frame.low, max($0, frame.low)))
                }
            }

            Text(spec.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func handle(
        _ spec: TuningSpec,
        _ value: Double,
        set: @escaping (Double) -> Void
    ) -> some View {
        Slider(
            value: Binding(get: { value }, set: set),
            in: spec.bounds
        )
        .accessibilityLabel(spec.label)
        .accessibilityValue(spec.unit.format(value))
    }

    private func reading(_ spec: TuningSpec, _ frame: TunableRange) -> String {
        spec.isSingle
            ? spec.unit.format(frame.low)
            : "\(spec.unit.format(frame.low)) – \(spec.unit.format(frame.high))"
    }
}

#endif
