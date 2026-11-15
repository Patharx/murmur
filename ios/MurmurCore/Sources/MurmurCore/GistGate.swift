import Foundation

/// A gist is skipped when the note is short in words or short in time. Either one is enough.
public enum GistGate {
    public static let minimumWords = 80
    public static let minimumAudioSeconds = 60

    public static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    public static func shouldSkip(words: Int, durationSeconds: Int?) -> Bool {
        if words < minimumWords { return true }
        if let durationSeconds, durationSeconds < minimumAudioSeconds { return true }
        return false
    }

    public static func shouldSkip(said: String, durationSeconds: Int?) -> Bool {
        shouldSkip(words: wordCount(in: said), durationSeconds: durationSeconds)
    }
}

/// Future sync reads this. Turning the flag on does not delete a copy already in Drive.
public enum DriveUpload {
    public static func shouldUpload(_ document: NoteDocument) -> Bool {
        !document.phoneOnly
    }
}
