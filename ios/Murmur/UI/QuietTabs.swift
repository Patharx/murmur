import SwiftUI

struct AskView: View {
    @Bindable var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(MurmurCopy.ask)
                    .font(MurmurType.screenTitle)
                    .foregroundStyle(Theme.text)
                    .tracking(-0.7)
                TextField("A word, or a question", text: $library.query)
                    .font(MurmurType.body)
                    .foregroundStyle(Theme.text)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neutral800, lineWidth: 1))
                Text(MurmurCopy.askHint)
                    .font(MurmurType.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVStack(spacing: 10) {
                    ForEach(results) { note in
                        NoteRowView(note: note)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    private var results: [NoteRow] {
        let query = library.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return [] }
        return library.visibleNotes
    }
}

struct WeeklyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Read back")
                .font(MurmurType.screenTitle)
                .foregroundStyle(Theme.text)
                .tracking(-0.7)
            Text(MurmurCopy.weeklyEmpty)
                .font(MurmurType.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(6)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.bg)
    }
}

struct YouView: View {
    var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(MurmurCopy.you)
                    .font(MurmurType.screenTitle)
                    .foregroundStyle(Theme.text)
                    .tracking(-0.7)
                VStack(alignment: .leading, spacing: 6) {
                    Text(MurmurCopy.notesLiveHere)
                        .font(MurmurType.rowTitle)
                        .foregroundStyle(Theme.text)
                    Text("Notes are files on this iPhone, in folders you can read. Copying them anywhere else comes later.")
                        .font(MurmurType.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neutral800, lineWidth: 1))
                Button {
                    library.rebuild()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MurmurCopy.rebuildIndex)
                            .font(MurmurType.rowTitle)
                            .foregroundStyle(Theme.accent400)
                        Text(MurmurCopy.rebuildDetail)
                            .font(MurmurType.secondary)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neutral800, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Theme.bg)
    }
}
