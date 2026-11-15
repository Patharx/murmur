import Foundation

public enum NotebookError: Error, Equatable {
    case escapesNotebook
    case missingNote
    case couldNotPlaceAudio
}

/// Files first, then the index. A save never waits on the network; there is no network here.
public final class Notebook {
    public let layout: NotebookLayout
    public let index: NoteIndex

    public init(root: URL, databaseURL: URL) throws {
        layout = NotebookLayout(root: root)
        try layout.ensureSkeleton()
        index = try NoteIndex(databaseURL: databaseURL)
    }

    @discardableResult
    public func save(_ document: NoteDocument, path existingPath: String?, now: Date = Date()) throws -> String {
        var document = document
        let folder = NotebookLayout.safeFolder(document.folder)
        document.folder = folder
        let folderURL = layout.root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let previous = try index.row(id: document.id)
        let excluding = existingPath.flatMap { ($0 as NSString).lastPathComponent }
        let filename = try layout.allocateFilename(
            folder: folder,
            created: document.created,
            title: document.title,
            excludingFilename: excluding
        )
        let relative = folder + "/" + filename
        let destination = try layout.url(relativePath: relative)
        let oldClips = existingPath.flatMap { try? load(path: $0).audioFiles } ?? []
        let moves = try audioMoves(document: &document, oldClips: oldClips, existingPath: existingPath, folder: folder, filename: filename)

        let previousMarkdown = FileManager.default.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination)
            : nil
        let text = NoteCodec.serialize(document)
        try Data(text.utf8).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: destination.path)

        var completed: [(URL, URL)] = []
        do {
            for move in moves {
                if FileManager.default.fileExists(atPath: move.destination.path) {
                    throw NotebookError.couldNotPlaceAudio
                }
                try FileManager.default.moveItem(at: move.source, to: move.destination)
                completed.append((move.destination, move.source))
            }
        } catch {
            for (nowAt, originally) in completed.reversed() {
                try? FileManager.default.moveItem(at: nowAt, to: originally)
            }
            if let previousMarkdown {
                try? previousMarkdown.write(to: destination, options: .atomic)
            } else if existingPath != relative {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }

        if let existingPath, existingPath != relative {
            let oldURL = try layout.url(relativePath: existingPath)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.removeItem(at: oldURL)
            }
        }

        try upsert(document, path: relative, file: destination, previous: previous, now: now)
        return relative
    }

    /// Writes a new voice note, then moves the recording beside it. A failed move removes the new file.
    @discardableResult
    public func storeVoiceNote(_ document: NoteDocument, audioSource: URL, now: Date = Date()) throws -> String {
        var document = document
        document.folder = NotebookLayout.unlabeled
        let filename = try layout.allocateFilename(
            folder: document.folder,
            created: document.created,
            title: document.title
        )
        let base = (filename as NSString).deletingPathExtension
        document.audioFilename = base + ".m4a"
        document.recordings = []
        document.kind = .voice
        let relative = document.folder + "/" + filename
        let destination = try layout.url(relativePath: relative)
        let audioURL = destination.deletingPathExtension().appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: audioURL.path) {
            throw NotebookError.couldNotPlaceAudio
        }
        try Data(NoteCodec.serialize(document).utf8).write(to: destination, options: .atomic)
        do {
            try FileManager.default.moveItem(at: audioSource, to: audioURL)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw NotebookError.couldNotPlaceAudio
        }
        try upsert(document, path: relative, file: destination, previous: nil, now: now)
        return relative
    }

    /// Puts the first recording beside a written note. Refuses to replace a clip that is already there.
    public func placeFirstClip(id: String, source: URL, now: Date = Date()) throws {
        guard let row = try index.row(id: id) else { throw NotebookError.missingNote }
        var document = try load(path: row.path)
        if !document.audioFiles.isEmpty { throw NotebookError.couldNotPlaceAudio }
        let base = ((row.path as NSString).lastPathComponent as NSString).deletingPathExtension
        document.audioFilename = base + ".m4a"
        if document.kind == .written { document.kind = .hybrid }
        let noteURL = try layout.url(relativePath: row.path)
        let audioURL = noteURL.deletingLastPathComponent().appendingPathComponent(document.audioFilename ?? "")
        if FileManager.default.fileExists(atPath: audioURL.path) { throw NotebookError.couldNotPlaceAudio }
        let previousMarkdown = try Data(contentsOf: noteURL)
        try Data(NoteCodec.serialize(document).utf8).write(to: noteURL, options: .atomic)
        do {
            try FileManager.default.moveItem(at: source, to: audioURL)
        } catch {
            try? previousMarkdown.write(to: noteURL, options: .atomic)
            throw NotebookError.couldNotPlaceAudio
        }
        try upsert(document, path: row.path, file: noteURL, previous: row, now: now)
    }

    /// Keeps every earlier clip and adds one more. The markdown is written first; a failed move rolls it back.
    @discardableResult
    public func addRecording(id: String, source: URL, addedAt: Date, liveText: String, modified: NoteTimestamp, now: Date = Date(), textAlreadyInserted: Bool = false) throws -> String {
        guard let row = try index.row(id: id) else { throw NotebookError.missingNote }
        let current = try load(path: row.path)
        let folderURL = layout.root.appendingPathComponent(current.folder, isDirectory: true)
        let clipName = try uniqueClipName(in: folderURL, addedAt: addedAt, title: current.title)
        let updated: NoteDocument
        if textAlreadyInserted {
            var next = current
            if next.kind == .written { next.kind = .hybrid }
            var files = next.audioFiles
            if !files.contains(clipName) { files.append(clipName) }
            next.audioFilename = files.first
            next.recordings = files.count > 1 ? files : []
            next.modified = modified
            updated = next
        } else {
            updated = NoteEditing.appendingClip(
                to: current,
                liveText: liveText,
                marker: ListeningText.addedMarker(at: addedAt),
                clipFilename: clipName,
                modified: modified
            )
        }
        let noteURL = try layout.url(relativePath: row.path)
        let previousMarkdown = try Data(contentsOf: noteURL)
        let clipURL = folderURL.appendingPathComponent(clipName)
        if FileManager.default.fileExists(atPath: clipURL.path) {
            throw NotebookError.couldNotPlaceAudio
        }
        try Data(NoteCodec.serialize(updated).utf8).write(to: noteURL, options: .atomic)
        do {
            try FileManager.default.moveItem(at: source, to: clipURL)
        } catch {
            try? previousMarkdown.write(to: noteURL, options: .atomic)
            throw NotebookError.couldNotPlaceAudio
        }
        try upsert(updated, path: row.path, file: noteURL, previous: row, now: now)
        return row.path
    }

    private struct AudioMove {
        var source: URL
        var destination: URL
    }

    private func audioMoves(
        document: inout NoteDocument,
        oldClips: [String],
        existingPath: String?,
        folder: String,
        filename: String
    ) throws -> [AudioMove] {
        guard let existingPath, !oldClips.isEmpty else { return [] }
        let oldFolder = (existingPath as NSString).deletingLastPathComponent
        let newBase = (filename as NSString).deletingPathExtension
        var clips = document.audioFiles
        if clips.isEmpty { clips = oldClips }
        if !clips.isEmpty {
            clips[0] = newBase + ".m4a"
        }
        document.audioFilename = clips.first
        document.recordings = clips.count > 1 ? clips : []
        var moves: [AudioMove] = []
        for (index, newName) in clips.enumerated() where index < oldClips.count {
            let fromRelative = (oldFolder.isEmpty ? "" : oldFolder + "/") + oldClips[index]
            let toRelative = folder + "/" + newName
            if fromRelative == toRelative { continue }
            let source = try layout.url(relativePath: fromRelative)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = try layout.url(relativePath: toRelative)
            moves.append(AudioMove(source: source, destination: destination))
        }
        return moves
    }

    private func uniqueClipName(in folder: URL, addedAt: Date, title: String) throws -> String {
        let stamp = NoteTimestamp(date: addedAt, text: Self.iso(addedAt))
        var collision = 0
        while collision < 100 {
            let name = NoteFilename.basename(created: stamp, title: title, collision: collision) + ".m4a"
            if !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                return name
            }
            collision += 1
        }
        throw NotebookError.couldNotPlaceAudio
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func upsert(_ document: NoteDocument, path: String, file: URL, previous: NoteRow?, now: Date) throws {
        _ = now
        let row = NoteRow(
            id: document.id,
            path: path,
            title: document.title,
            folder: document.folder,
            kind: document.kind.rawValue,
            created: document.created.date,
            duration: document.durationSeconds,
            hasSummary: document.hasSummary,
            body: document.said,
            localMtime: fileMtimeMillis(file),
            syncedMtime: previous?.syncedMtime,
            driveId: previous?.driveId,
            driveRev: previous?.driveRev,
            phoneOnly: document.phoneOnly
        )
        try index.upsert(row)
    }

    public func load(path: String) throws -> NoteDocument {
        let url = try layout.url(relativePath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw NotebookError.missingNote }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try NoteCodec.parse(text)
    }

    public func rows(folder: String? = nil) throws -> [NoteRow] {
        let all = try index.allRows()
        guard let folder, !folder.isEmpty else { return all }
        return all.filter { $0.folder == folder }
    }

    public func row(id: String) throws -> NoteRow? {
        try index.row(id: id)
    }

    public func search(_ query: String) throws -> [NoteRow] {
        try index.search(query)
    }

    public func markSynced(id: String, syncedMtime: Int64) throws {
        guard var row = try index.row(id: id) else { return }
        row.syncedMtime = syncedMtime
        try index.upsert(row)
    }

    /// Drops an empty markdown file. Audio beside it is left where it is.
    @discardableResult
    public func discardIfEmpty(path: String) throws -> Bool {
        let document = try load(path: path)
        let blank = NoteDraft.isEmpty(title: document.title, said: document.said)
        guard blank else { return false }
        let url = try layout.url(relativePath: path)
        try FileManager.default.removeItem(at: url)
        try index.remove(id: document.id)
        return true
    }

    public func rebuildIndex() throws {
        let previous = try index.allRows()
        let byID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        try index.removeAll()
        let files = try markdownFiles()
        for file in files {
            let relative = layout.relativePath(for: file)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let mtime = fileMtimeMillis(file)
            if let document = try? NoteCodec.parse(text) {
                let row = NoteRow(
                    id: document.id,
                    path: relative,
                    title: document.title,
                    folder: document.folder,
                    kind: document.kind.rawValue,
                    created: document.created.date,
                    duration: document.durationSeconds,
                    hasSummary: document.hasSummary,
                    body: document.said,
                    localMtime: mtime,
                    syncedMtime: byID[document.id]?.syncedMtime,
                    driveId: byID[document.id]?.driveId,
                    driveRev: byID[document.id]?.driveRev,
                    phoneOnly: document.phoneOnly
                )
                try index.upsert(row)
            } else {
                let folder = (relative as NSString).deletingLastPathComponent
                let name = file.deletingPathExtension().lastPathComponent
                let row = NoteRow(
                    id: "unparsed:" + relative,
                    path: relative,
                    title: name.replacingOccurrences(of: "-", with: " "),
                    folder: folder == "." ? NotebookLayout.oddsAndEnds : folder,
                    kind: "written",
                    created: Date(timeIntervalSince1970: Double(mtime) / 1000),
                    duration: nil,
                    hasSummary: false,
                    body: text,
                    localMtime: mtime,
                    syncedMtime: nil
                )
                try index.upsert(row)
            }
        }
    }

    private func markdownFiles() throws -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: layout.root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasPrefix(".") || url.path.contains("/.murmur/") {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension.lowercased() == "md" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func fileMtimeMillis(_ url: URL) -> Int64 {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

public enum NoteDraft {
    public static func isEmpty(title: String, said: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
