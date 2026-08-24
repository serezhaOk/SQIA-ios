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

                // A workbench, not a feature. The sound has one and is done
                // with it — its numbers ship as `Tuning.tuned` — so the slot
                // goes to the field, which is still being decided and can
                // only be decided by looking at it.
                #if DEBUG
                    Section {
                        NavigationLink {
                            FieldTuningView(model: model)
                        } label: {
                            Label("Field", systemImage: "slider.horizontal.3")
                        }
                    } footer: {
                        Text(
                            model.fieldTuning.isDefault
                                ? "The field is where it was last written down."
                                : "Moved from the look this build ships with.")
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
