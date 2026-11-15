import MurmurCore
import SwiftUI

struct ComposeView: View {
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var said = ""
    @State private var folder = NotebookLayout.written
    @State private var path: String?
    @State private var documentID = ULID().description
    @State private var created = NoteClock.stamp()
    @State private var saveTask: Task<Void, Never>?
    @State private var dictating = false
    @State private var session = ListeningSession()
    @State private var pending = ""

    private let folders = ["Written", "Reflections", "Reading", "Odds and ends"]

    var body: some View {
        VStack(spacing: 0) {
            header
            TextField("Title", text: $title)
                .font(MurmurType.composeTitle)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            TextEditor(text: $said)
                .font(MurmurType.body)
                .foregroundStyle(Theme.text.opacity(0.8))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .lineSpacing(6)
            if dictating {
                dictationBar
            }
            footer
        }
        .background(Theme.bg)
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: said) { _, _ in scheduleSave() }
        .onChange(of: folder) { _, _ in scheduleSave() }
        .onChange(of: session.liveText) { _, newValue in
            if dictating { pending = newValue }
        }
    }

    private var header: some View {
        HStack {
            Button(MurmurCopy.close) { close() }
                .font(MurmurType.secondary)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Written")
                .font(MurmurType.chip)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button(MurmurCopy.keep) {
                saveNow()
                dismiss()
            }
            .font(MurmurType.custom(15, weight: .medium, relativeTo: .body))
            .foregroundStyle(Theme.accent400)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(MurmurCopy.keptAsYouType, systemImage: "checkmark")
                .font(MurmurType.meta)
                .foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(folders, id: \.self) { name in
                        FolderChip(title: NotebookLayout.chipLabel(for: name), active: folder == name) {
                            folder = name
                        }
                    }
                }
            }
            if !dictating {
                HStack(spacing: 16) {
                    Text("Aa")
                        .font(MurmurType.secondary)
                        .foregroundStyle(Theme.accent400)
                        .accessibilityLabel("Plain text")
                    Button("List") { insert("\n- ") }
                        .buttonStyle(.plain)
                    Button("Quote") { insert("\n> ") }
                        .buttonStyle(.plain)
                    Spacer()
                    Button {
                        Task { await beginDictation() }
                    } label: {
                        Label(MurmurCopy.sayItInstead, systemImage: "mic")
                            .font(MurmurType.secondary)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent400)
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.bg)
    }

    private var dictationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pending.isEmpty ? " " : pending)
                .font(MurmurType.body)
                .foregroundStyle(Theme.accent400.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("Carries on where you left off")
                    .font(MurmurType.meta)
                    .foregroundStyle(Theme.accent300)
                Spacer()
                Button("Done") { finishDictation() }
                    .font(MurmurType.custom(15, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Theme.accent400)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Theme.accent800.opacity(0.5), Theme.surface.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, 20)
    }

    private func insert(_ prefix: String) {
        if said.isEmpty {
            said = prefix.trimmingCharacters(in: .newlines)
        } else {
            said += prefix
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard !NoteDraft.isEmpty(title: title, said: said) else { return }
        var document = NoteDocument(
            id: documentID,
            created: created,
            modified: NoteClock.stamp(),
            kind: .written,
            folder: folder,
            title: title,
            said: said
        )
        if let existing = path, let current = library.load(path: existing), current.kind == .hybrid {
            document.kind = .hybrid
            document.audioFilename = current.audioFilename
            document.durationSeconds = current.durationSeconds
        }
        path = library.save(document, path: path)
    }

    private func close() {
        saveTask?.cancel()
        if NoteDraft.isEmpty(title: title, said: said), let path {
            library.discardIfEmpty(path: path)
        } else {
            saveNow()
        }
        if dictating { session.abandon() }
        dismiss()
    }

    private func beginDictation() async {
        dictating = true
        pending = ""
        await session.start()
    }

    private func finishDictation() {
        dictating = false
        let captured = session.stop()
        let spoken = (captured?.liveText ?? pending).trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            if said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                said = spoken
            } else if said.hasSuffix(" ") || said.hasSuffix("\n") {
                said += spoken
            } else {
                said += " " + spoken
            }
        }
        pending = ""
        saveNow()
        guard let captured, let path, var document = library.load(path: path) else { return }
        document.said = said
        document.folder = folder
        document.title = title
        _ = library.attachDictation(path: path, captured: captured, to: document)
    }
}
