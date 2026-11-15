import Foundation

/// Text rules for a file transcript and for a later clip. The files themselves are moved by `Notebook`.
public enum NoteEditing {
    /// Inserts `block` at a UTF-16 cursor. A cursor at the end appends.
    public static func insert(_ said: String, utf16 cursor: Int, block: String) -> String {
        let ns = said as NSString
        let location = min(max(0, cursor), ns.length)
        return ns.replacingCharacters(in: NSRange(location: location, length: 0), with: block)
    }

    public static func clipBlock(marker: String, liveText: String) -> String {
        let spoken = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        return marker + "\n\n" + spoken
    }
    /// The file transcript replaces the live draft only when nobody has edited the note since.
    /// The title is left alone, so the file does not move out from under an open note.
    public static func applyingFileTranscript(
        to document: NoteDocument,
        liveDraft: String,
        authoritative: String,
        bookmarks: [TimeInterval],
        duration: TimeInterval
    ) -> NoteDocument? {
        guard document.said == liveDraft else { return nil }
        var next = document
        let reconciled = ListeningText.reconcile(live: liveDraft, authoritative: authoritative)
        next.said = ListeningText.merge(transcript: reconciled, bookmarks: bookmarks, duration: duration)
        return next
    }

    /// Replaces the words after one "— Added …" marker when they are still the live draft.
    public static func applyingClipTranscript(
        said: String,
        marker: String,
        liveDraft: String,
        authoritative: String
    ) -> String? {
        let draft = liveDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = marker + "\n\n" + draft
        guard said.contains(tail) else { return nil }
        let spoken = authoritative.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = spoken.isEmpty ? draft : spoken
        return said.replacingOccurrences(of: tail, with: marker + "\n\n" + replacement)
    }

    /// Replaces the one untouched live draft, including one that was inserted mid-sentence.
    public static func replacingDraft(said: String, liveDraft: String, authoritative: String) -> String? {
        let draft = liveDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return nil }
        let pieces = said.components(separatedBy: draft)
        guard pieces.count == 2 else { return nil }
        let spoken = authoritative.trimmingCharacters(in: .whitespacesAndNewlines)
        if spoken.isEmpty { return said }
        return pieces.joined(separator: spoken)
    }

    /// Appends a later recording. Earlier clips stay listed, and the body gains a time marker.
    public static func appendingClip(
        to document: NoteDocument,
        liveText: String,
        marker: String,
        clipFilename: String,
        modified: NoteTimestamp
    ) -> NoteDocument {
        var next = document
        let spoken = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = marker + "\n\n" + spoken
        if next.said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.said = block
        } else {
            next.said += "\n\n" + block
        }
        if next.kind == .written { next.kind = .hybrid }
        var files = next.audioFiles
        if !files.contains(clipFilename) { files.append(clipFilename) }
        next.audioFilename = files.first
        next.recordings = files.count > 1 ? files : []
        next.modified = modified
        return next
    }
}
