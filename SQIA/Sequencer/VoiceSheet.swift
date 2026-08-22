// The sound picker.
//
// The web slides a styled panel up over the sequencer. On a phone the thing
// that belongs here is the sheet iOS already has: a grouped list, a title, a
// Done button, a checkmark on the row that is set. It reads as part of the
// system rather than as a web page in a frame, and it gets voice-over,
// Dynamic Type and the scroll behaviour for free.
//
// A deliberate departure from the port's usual rule, at the owner's call:
// modals and buttons follow the platform, the sequencer itself follows the
// web.

import SQIACore
import SwiftUI

struct VoiceSheet: View {
    let model: SequencerModel
    let onPick: (SynthPreset) -> Void

    private var selected: Int { model.state.activeTrack.voiceIndex }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(VoiceCatalog.offered, id: \.rawValue) { preset in
                        row(preset)
                    }
                } footer: {
                    Text("The patch drifts once a bar, and every note is rolled fresh.")
                }

                // Twenty-nine sliders with no explanation is a workbench,
                // not a feature — it is how the sound got tuned, and it stays
                // where the tuning happens. The numbers it produced ship as
                // `Tuning.tuned`; the panel does not.
                #if DEBUG
                    Section {
                        NavigationLink {
                            TuningView(model: model)
                        } label: {
                            Label("Tuning", systemImage: "slider.horizontal.3")
                        }
                    } footer: {
                        Text(
                            model.tuning.isDefault
                                ? "Every voice is where it was tuned to."
                                : "Moved from the tuning this build ships with.")
                    }
                #endif
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ preset: SynthPreset) -> some View {
        Button {
            onPick(preset)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.label)
                        .font(.body)
                    Text(preset.hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if preset.rawValue == selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(preset.rawValue == selected ? [.isSelected] : [])
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            VoiceSheet(
                model: SequencerModel(store: InMemoryProjectStore()), onPick: { _ in })
        }
}
