// The key picker: which note the grid starts from, and which scale it walks.
//
// The web cycles both on tap, a label at a time. On a phone, picking one of
// twelve notes by tapping eleven times is not the same gesture — so this is
// a system sheet with the twelve laid out to choose from, and the five
// scales under them.
//
// A deliberate departure from the port's usual rule, at the owner's call:
// modals and buttons follow the platform, the sequencer itself follows the
// web.

import SQIACore
import SwiftUI

struct KeySheet: View {
    let rootPc: Int
    let scaleIndex: Int
    let onPickRoot: (Int) -> Void
    let onPickScale: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Wide enough for a sharp, and even so the twelve sit in a tidy grid.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        NavigationStack {
            List {
                Section("Note") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Music.noteNames.indices, id: \.self) { pc in
                            noteButton(pc)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(Music.scales.indices, id: \.self) { index in
                        scaleRow(index)
                    }
                } header: {
                    Text("Scale")
                } footer: {
                    Text("The key moves the pitches. Whatever is drawn stays drawn.")
                }
            }
            .navigationTitle("Key")
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

    private func noteButton(_ pc: Int) -> some View {
        let isSelected = pc == rootPc
        return Button {
            onPickRoot(pc)
        } label: {
            Text(Music.noteNames[pc])
                .font(.body.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .tint(isSelected ? Color.accentColor : Color.secondary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func scaleRow(_ index: Int) -> some View {
        let isSelected = index == scaleIndex
        return Button {
            onPickScale(index)
        } label: {
            HStack {
                Text(Music.scales[index].name.capitalized)
                    .font(.body)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            KeySheet(rootPc: 0, scaleIndex: 0, onPickRoot: { _ in }, onPickScale: { _ in })
        }
}
