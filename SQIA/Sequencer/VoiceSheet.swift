// The sound picker: a list of voices, the current one ticked.
//
// The web slides a sheet up over the sequencer, at most three quarters of
// the screen, with a grip at the top. A system sheet with a detent gets to
// the same place; the styling is the web's.

import SwiftUI

struct VoiceSheet: View {
    let selected: Int
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sound")
                .manrope(.semibold, 15)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(VoiceCatalog.all.enumerated()), id: \.element.id) {
                        index, voice in
                        row(index: index, voice: voice)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sheet)
        .presentationDetents([.fraction(0.76)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
    }

    private func row(index: Int, voice: Voice) -> some View {
        Button {
            onPick(index)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.label)
                        .manrope(.regular, 16)
                        .foregroundStyle(Palette.ui)
                    Text(voice.hint)
                        .manrope(.regular, 13)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ui)
                    .opacity(index == selected ? 1 : 0)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(index == selected ? Palette.menuPressed : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            VoiceSheet(selected: 0, onPick: { _ in })
        }
}
