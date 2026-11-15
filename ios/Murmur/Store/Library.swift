import Foundation
import MurmurCore

@MainActor
@Observable
final class Library {
    private let notebook: Notebook
    private(set) var notes: [NoteRow] = []
    var folder: String?
    var query = ""
    var problem: String?

    static let folderOrder = NotebookLayout.chipFolders

    init(notebook: Notebook) {
        self.notebook = notebook
        reload()
    }

    static func live() -> Library? {
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let root = documents.appendingPathComponent("Murmur", isDirectory: true)
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Murmur", isDirectory: true)
            let database = support.appendingPathComponent("notes.sqlite")
            return Library(notebook: try Notebook(root: root, databaseURL: database))
        } catch {
            return nil
        }
    }

    var visibleNotes: [NoteRow] {
        (try? notebook.rows(folder: folder)) ?? notes.filter { folder == nil || $0.folder == folder }
    }

    var searchResults: [NoteRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        return (try? notebook.search(trimmed)) ?? []
    }

    func headline(now: Date = Date(), calendar: Calendar = .current) -> String {
        let todays = notes.filter { calendar.isDate($0.created, inSameDayAs: now) }
        let shaped = todays.map { row in
            TodayNote(folder: row.folder, threads: threads(for: row))
        }
        return TodayCopy.headline(notesFromToday: shaped, folder: folder)
    }

    func reload() {
        do {
            notes = try notebook.rows()
            problem = nil
        } catch {
            problem = "The list couldn't be read. The files are still on this iPhone."
        }
    }

    func load(path: String) -> NoteDocument? {
        try? notebook.load(path: path)
    }

    func audioURL(for path: String, filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        guard let noteURL = try? notebook.layout.url(relativePath: path) else { return nil }
        let url = noteURL.deletingLastPathComponent().appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fileURL(path: String) -> URL? {
        try? notebook.layout.url(relativePath: path)
    }

    @discardableResult
    func save(_ document: NoteDocument, path: String?, now: Date = Date()) -> String? {
        do {
            let saved = try notebook.save(document, path: path, now: now)
            reload()
            problem = nil
            return saved
        } catch {
            problem = "That note stayed in memory. It couldn't be written just then."
            return nil
        }
    }

    func discardIfEmpty(path: String) {
        _ = try? notebook.discardIfEmpty(path: path)
        reload()
    }

    func rebuild() {
        do {
            try notebook.rebuildIndex()
            reload()
        } catch {
            problem = "The index couldn't be rebuilt. The files are still there."
        }
    }

    /// Writes the voice note immediately, then replaces the words with the file transcript when it arrives.
    func keepVoiceNote(captured: CapturedAudio) {
        let stamp = NoteClock.stamp(captured.started)
        let said = ListeningText.merge(
            transcript: captured.liveText,
            bookmarks: captured.bookmarks,
            duration: captured.duration
        )
        let document = NoteDocument(
            id: ULID().description,
            created: stamp,
            modified: stamp,
            kind: .voice,
            folder: NotebookLayout.unlabeled,
            title: Self.title(from: said, at: captured.started),
            said: said,
            durationSeconds: max(0, Int(captured.duration.rounded()))
        )
        do {
            let path = try notebook.storeVoiceNote(document, audioSource: captured.url, now: captured.started)
            reload()
            guard let audio = audioFiles(path: path).first else { return }
            let id = document.id
            Task { [weak self] in
                let authoritative = (try? await FileTranscriber.transcribe(url: audio)) ?? ""
                await MainActor.run {
                    self?.applyFileTranscript(
                        id: id,
                        live: said,
                        authoritative: authoritative,
                        bookmarks: captured.bookmarks,
                        duration: captured.duration
                    )
                }
            }
        } catch {
            problem = "The words were kept. The audio didn't land beside them."
        }
    }

    func placeFirstClip(id: String, source: URL, liveDraft: String) {
        do {
            try notebook.placeFirstClip(id: id, source: source)
            reload()
            guard let row = try? notebook.row(id: id), let audio = audioFiles(path: row.path).first else { return }
            Task { [weak self] in
                let authoritative = (try? await FileTranscriber.transcribe(url: audio)) ?? ""
                await MainActor.run {
                    self?.applyTrailingDraft(id: id, liveDraft: liveDraft, authoritative: authoritative)
                }
            }
        } catch {
            problem = "The words were kept. The audio didn't land beside them."
        }
    }

    func addClip(id: String, captured: CapturedAudio, textAlreadyInserted: Bool = false, marker: String? = nil) {
        let modified = NoteClock.stamp()
        let clipMarker = marker ?? ListeningText.addedMarker(at: captured.started)
        do {
            _ = try notebook.addRecording(
                id: id,
                source: captured.url,
                addedAt: captured.started,
                liveText: captured.liveText,
                modified: modified,
                textAlreadyInserted: textAlreadyInserted
            )
            reload()
            guard let row = try? notebook.row(id: id), let audio = audioFiles(path: row.path).last else { return }
            Task { [weak self] in
                let authoritative = (try? await FileTranscriber.transcribe(url: audio)) ?? ""
                await MainActor.run {
                    self?.applyClipTranscript(id: id, marker: clipMarker, liveDraft: captured.liveText, authoritative: authoritative)
                }
            }
        } catch {
            problem = "The earlier recording is still there. The new one didn't land."
        }
    }

    private func applyFileTranscript(id: String, live: String, authoritative: String, bookmarks: [TimeInterval], duration: TimeInterval) {
        guard let row = try? notebook.row(id: id), let document = load(path: row.path) else { return }
        guard var next = NoteEditing.applyingFileTranscript(
            to: document,
            liveDraft: live,
            authoritative: authoritative,
            bookmarks: bookmarks,
            duration: duration
        ) else { return }
        next.modified = NoteClock.stamp()
        _ = save(next, path: row.path)
    }

    private func applyTrailingDraft(id: String, liveDraft: String, authoritative: String) {
        guard let row = try? notebook.row(id: id), var document = load(path: row.path) else { return }
        guard let said = NoteEditing.replacingDraft(said: document.said, liveDraft: liveDraft, authoritative: authoritative) else { return }
        document.said = said
        document.modified = NoteClock.stamp()
        _ = save(document, path: row.path)
    }

    private func applyClipTranscript(id: String, marker: String, liveDraft: String, authoritative: String) {
        guard let row = try? notebook.row(id: id), var document = load(path: row.path) else { return }
        guard let said = NoteEditing.applyingClipTranscript(
            said: document.said,
            marker: marker,
            liveDraft: liveDraft,
            authoritative: authoritative
        ) else { return }
        document.said = said
        document.modified = NoteClock.stamp()
        _ = save(document, path: row.path)
    }

    func audioFiles(path: String) -> [URL] {
        guard let document = load(path: path), let noteURL = fileURL(path: path) else { return [] }
        return document.audioFiles.map { noteURL.deletingLastPathComponent().appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func threads(for row: NoteRow) -> [String] {
        (try? notebook.load(path: row.path).threads) ?? []
    }

    static func title(from said: String, at date: Date) -> String {
        let line = said
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("—") } ?? ""
        if line.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = "H:mm"
            return formatter.string(from: date)
        }
        if line.count <= 60 { return line }
        return String(line.prefix(60)).trimmingCharacters(in: .whitespaces)
    }
}
