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
                    The shared reverb. Two of these are not the web's: it \
                    convolves against seven seconds of white noise under an \
                    envelope, so its tail is longer and stays bright, while \
                    this one is a feedback network that darkens as it fades. \
                    Raise decay and damping to move towards it.
                    """)
            }
        }
        .navigationTitle("Tuning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") { model.resetAllTuning() }
                    .disabled(model.tuning.isWeb)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(copied ? "Copied" : "Copy") { copy() }
                    .disabled(model.tuning.isWeb)
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
        let moved = frame != Tuning.web[spec.knob]

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

            if spec.isSingle {
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

/// Presented on its own, from the meter.
struct TuningSheet: View {
    let model: SequencerModel

    var body: some View {
        NavigationStack {
            TuningView(model: model)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
