import MurmurCore
import SwiftUI

struct TodayView: View {
    @Bindable var library: Library
    var compose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    chips
                    if let problem = library.problem {
                        Text(problem)
                            .font(MurmurType.secondary)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    notes
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationDestination(for: String.self) { id in
                NoteDetailView(library: library, id: id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TodayCopy.dateLabel(for: Date(), calendar: .current))
                .font(MurmurType.sectionLabel)
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .top) {
                Text(library.headline())
                    .font(MurmurType.todayHeadline)
                    .foregroundStyle(Theme.text)
                    .tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                IconButton(icon: "pencil-simple", label: "Write a note", action: compose)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FolderChip(title: "All", active: library.folder == nil) {
                    library.folder = nil
                }
                ForEach(Library.folderOrder, id: \.self) { folder in
                    FolderChip(
                        title: NotebookLayout.chipLabel(for: folder),
                        active: library.folder == folder
                    ) {
                        library.folder = folder
                    }
                }
            }
        }
    }

    private var notes: some View {
        LazyVStack(spacing: 10) {
            ForEach(library.visibleNotes) { note in
                NavigationLink(value: note.id) {
                    NoteRowView(note: note)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NoteRowView: View {
    var note: NoteRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.accent.opacity(0.14))
                .frame(width: 30, height: 30)
                .overlay {
                    PhosphorIcon(name: note.kind == "written" ? "text-align-left" : "microphone", size: 16)
                        .foregroundStyle(Theme.accent400)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(MurmurType.rowTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if !note.body.isEmpty {
                    Text(note.body)
                        .font(MurmurType.caption)
                        .foregroundStyle(Theme.text.opacity(0.5))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    meta(time)
                    if let duration = note.duration, duration > 0 {
                        dot
                        meta(ListeningText.timer(TimeInterval(duration)))
                    }
                    dot
                    meta(NotebookLayout.chipLabel(for: note.folder))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neutral800, lineWidth: 1))
    }

    private var time: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "H:mm"
        return formatter.string(from: note.created)
    }

    private func meta(_ value: String) -> some View {
        Text(value)
            .font(MurmurType.meta)
            .foregroundStyle(Theme.textQuaternary)
            .monospacedDigit()
    }

    private var dot: some View {
        Circle()
            .fill(Theme.text.opacity(0.3))
            .frame(width: 2, height: 2)
    }
}
