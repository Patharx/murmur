import Foundation

public enum NotebookLayoutError: Error, Equatable {
    case escapesNotebook
}

public struct NotebookLayout: Equatable, Sendable {
    public static let mirroredFolderName = "Murmur"
    public static let oddsAndEnds = "Odds and ends"
    public static let written = "Written"
    public static let defaultFolders = ["Walks", "Reflections", "Written", "Reading", "Odds and ends"]

    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func ensureSkeleton() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in Self.defaultFolders {
            try manager.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        try manager.createDirectory(at: root.appendingPathComponent("Recaps/weekly", isDirectory: true), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent(".murmur", isDirectory: true), withIntermediateDirectories: true)
    }

    public static func safeFolder(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return oddsAndEnds }
        if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains("..") { return oddsAndEnds }
        if trimmed.hasPrefix(".") { return oddsAndEnds }
        return trimmed
    }

    public static func chipLabel(for folder: String) -> String {
        folder == oddsAndEnds ? "Odds & ends" : folder
    }

    public func relativePath(for url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        var path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath) {
            path.removeFirst(rootPath.count)
        }
        if path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    public func url(relativePath: String) throws -> URL {
        let clean = relativePath.replacingOccurrences(of: "\\", with: "/")
        if clean.hasPrefix("/") || clean.contains("..") || clean.contains("\u{0}") {
            throw NotebookLayoutError.escapesNotebook
        }
        let url = root.appendingPathComponent(clean).standardizedFileURL
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path
        let path = url.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            throw NotebookLayoutError.escapesNotebook
        }
        return url
    }

    /// The markdown filename to use inside `folder`, avoiding names that are already taken.
    public func allocateFilename(
        folder: String,
        created: NoteTimestamp,
        title: String,
        excludingFilename: String? = nil
    ) throws -> String {
        let safe = Self.safeFolder(folder)
        let directory = root.appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var collision = 0
        while collision < 100 {
            let filename = NoteFilename.basename(created: created, title: title, collision: collision) + ".md"
            if filename == excludingFilename { return filename }
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) { return filename }
            collision += 1
        }
        return NoteFilename.basename(created: created, title: title, collision: 0) + "-" + ULID().description + ".md"
    }
}
