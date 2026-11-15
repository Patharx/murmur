import Foundation

public enum NotebookError: Error, Equatable {
    case escapesNotebook
    case missingNote
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

        if let audio = document.audioFilename, let existingPath {
            let oldFolder = (existingPath as NSString).deletingLastPathComponent
            let oldAudio = (oldFolder.isEmpty ? "" : oldFolder + "/") + audio
            let newAudioName = destination.deletingPathExtension().lastPathComponent + ".m4a"
            if oldAudio != folder + "/" + newAudioName {
                if let oldURL = try? layout.url(relativePath: oldAudio),
                   FileManager.default.fileExists(atPath: oldURL.path) {
                    let newURL = folderURL.appendingPathComponent(newAudioName)
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        try FileManager.default.removeItem(at: newURL)
                    }
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                }
            }
            document.audioFilename = newAudioName
        }

        let text = NoteCodec.serialize(document)
        try Data(text.utf8).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: destination.path)

        if let existingPath, existingPath != relative {
            let oldURL = try layout.url(relativePath: existingPath)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.removeItem(at: oldURL)
            }
        }

        let millis = fileMtimeMillis(destination)
        let row = NoteRow(
            id: document.id,
            path: relative,
            title: document.title,
            folder: folder,
            kind: document.kind.rawValue,
            created: document.created.date,
            duration: document.durationSeconds,
            hasSummary: document.hasSummary,
            body: document.said,
            localMtime: millis,
            syncedMtime: previous?.syncedMtime
        )
        try index.upsert(row)
        return relative
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
                    syncedMtime: byID[document.id]?.syncedMtime
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
