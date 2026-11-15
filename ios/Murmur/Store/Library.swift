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

    static let folderOrder = ["Written", "Walks", "Reflections", "Reading", "Odds and ends"]

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
        let base: [NoteRow]
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = (try? notebook.rows(folder: folder)) ?? notes.filter { folder == nil || $0.folder == folder }
        } else {
            let found = (try? notebook.search(query)) ?? []
            base = found.filter { folder == nil || $0.folder == folder }
        }
        return base
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
        let said = ListeningText.merge(transcript: captured.liveText, bookmarks: captured.bookmarks)
        let document = NoteDocument(
            id: ULID().description,
            created: stamp,
            modified: stamp,
            kind: .voice,
            folder: NotebookLayout.oddsAndEnds,
            title: Self.title(from: said, at: captured.started),
            said: said,
            audioFilename: "audio.m4a",
            durationSeconds: max(0, Int(captured.duration.rounded()))
        )
        guard let path = save(document, path: nil, now: captured.started) else { return }
        guard let noteURL = fileURL(path: path) else { return }
        let destination = noteURL.deletingPathExtension().appendingPathExtension(CaptureFormat.fileExtension)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: captured.url, to: destination)
        } catch {
            problem = "The audio is still in a temporary file. The words were kept."
        }
        if var stored = load(path: path) {
            stored.audioFilename = destination.lastPathComponent
            _ = save(stored, path: path, now: captured.started)
        }
        let bookmarks = captured.bookmarks
        let live = said
        let id = document.id
        Task { [weak self] in
            let authoritative = (try? await FileTranscriber.transcribe(url: destination)) ?? ""
            await MainActor.run {
                self?.applyTranscript(id: id, live: live, authoritative: authoritative, bookmarks: bookmarks)
            }
        }
    }

    func attachDictation(path: String, captured: CapturedAudio, to document: NoteDocument) -> String? {
        var document = document
        document.kind = .hybrid
        document.modified = NoteClock.stamp()
        let previousAudio = document.audioFilename
        document.audioFilename = document.audioFilename ?? "dictation.m4a"
        guard let savedPath = save(document, path: path) else { return nil }
        guard let noteURL = fileURL(path: savedPath) else { return savedPath }
        let destination = noteURL.deletingPathExtension().appendingPathExtension(CaptureFormat.fileExtension)
        if let previousAudio {
            let old = noteURL.deletingLastPathComponent().appendingPathComponent(previousAudio)
            if old.path != destination.path, FileManager.default.fileExists(atPath: old.path) {
                let kept = noteURL.deletingLastPathComponent().appendingPathComponent(
                    noteURL.deletingPathExtension().lastPathComponent + "-earlier.m4a"
                )
                if !FileManager.default.fileExists(atPath: kept.path) {
                    try? FileManager.default.moveItem(at: old, to: kept)
                }
            }
        }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: captured.url, to: destination)
        if var stored = load(path: savedPath) {
            stored.audioFilename = destination.lastPathComponent
            stored.kind = .hybrid
            if stored.durationSeconds == nil {
                stored.durationSeconds = max(0, Int(captured.duration.rounded()))
            }
            return save(stored, path: savedPath)
        }
        return savedPath
    }

    private func applyTranscript(id: String, live: String, authoritative: String, bookmarks: [TimeInterval]) {
        guard let row = try? notebook.row(id: id), var document = load(path: row.path) else { return }
        let merged = ListeningText.reconcile(live: live, authoritative: authoritative)
        document.said = ListeningText.merge(transcript: merged, bookmarks: bookmarks)
        document.modified = NoteClock.stamp()
        if document.title == Self.title(from: live, at: document.created.date),
           !authoritative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.title = Self.title(from: document.said, at: document.created.date)
        }
        _ = save(document, path: row.path)
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
