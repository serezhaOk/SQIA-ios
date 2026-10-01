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
    let onPick: (TrackVoice) -> Void

    private var selected: Int { model.state.activeTrack.voiceIndex }

    @Environment(\.dismiss) private var dismiss
    /// Who is signed in, for the workbench at the bottom of the list.
    @Environment(\.accountEmail) private var accountEmail

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(VoiceCatalog.offered(model.bank), id: \.self) { voice in
                        row(voice)
                    }
                } footer: {
                    Text("Every note is rolled fresh, so a pattern never plays quite the same twice.")
                }

                // A workbench, not a feature. The sound has one and is done
                // with it — its numbers ship as `Tuning.tuned` — so the slot
                // goes to the field, which is still being decided and can
                // only be decided by looking at it.
                //
                // It used to be `#if DEBUG`, which put it out of reach on the
                // one build the field has to be judged on: a real phone, over
                // TestFlight. `Workbench` opens it there for the account that
                // does the tuning and for nobody else.
                if Workbench.isOpen(to: accountEmail) {
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
                }
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

    private func row(_ voice: TrackVoice) -> some View {
        let plus = VoiceCatalog.isPlus(voice, model.bank)
        let pending = model.pendingVoice == voice
        return Button {
            onPick(voice)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(VoiceCatalog.label(voice, model.bank))
                            .font(.body)
                        if plus {
                            // The Plus diamond, as on the mixer's locked pane.
                            Image("PlusDiamond")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("SQIA Plus")
                        }
                    }
                    Text(VoiceCatalog.hint(voice, model.bank))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // Only once the wait is long enough to notice: a quick
                    // download should look like no download at all.
                    if pending && model.pendingShowsProgress {
                        ProgressView(value: model.pendingProgress)
                            .progressViewStyle(.linear)
                            .padding(.top, 4)
                            .accessibilityLabel("Downloading")
                    }
                }
                Spacer(minLength: 12)
                if voice.index == selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.2), value: model.pendingShowsProgress)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(voice.index == selected ? [.isSelected] : [])
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            VoiceSheet(
                model: SequencerModel(store: InMemoryProjectStore()), onPick: { _ in })
        }
}
