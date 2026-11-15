import Foundation

/// Text rules for a file transcript and for a later clip. The files themselves are moved by `Notebook`.
public enum NoteEditing {
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

    /// Replaces a live draft that was appended at the end of a written note.
    public static func replacingTrailingDraft(said: String, liveDraft: String, authoritative: String) -> String? {
        let draft = liveDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty, said.hasSuffix(draft) else { return nil }
        let spoken = authoritative.trimmingCharacters(in: .whitespacesAndNewlines)
        if spoken.isEmpty { return said }
        return String(said.dropLast(draft.count)) + spoken
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
