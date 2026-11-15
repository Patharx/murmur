import Foundation

public enum CaptureFormat {
    public static let bitRate = 32_000
    public static let channelCount = 1
    public static let sampleRate = 22_050.0
    public static let fileExtension = "m4a"
}

public enum WaveformMetrics {
    public static let barCount = 40
    public static let minimumHeight = 6.0
    public static let maximumHeight = 68.0

    /// Maps an average power in decibels to a bar height. Silence stays at the floor.
    public static func height(decibels: Float) -> Double {
        let clamped = min(0, max(-50, decibels))
        let unit = Double((clamped + 50) / 50)
        return minimumHeight + unit * (maximumHeight - minimumHeight)
    }
}

public enum ListeningText {
    public static func timer(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    public static func bookmarkMarker(at seconds: TimeInterval) -> String {
        "\n\n— \(timer(seconds))\n\n"
    }

    /// "— Added 3:42 PM". The clock is the moment the later clip was kept.
    public static func addedMarker(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return "— Added \(formatter.string(from: date))"
    }

    /// The file transcript replaces the live line, unless the file produced nothing.
    public static func reconcile(live: String, authoritative: String) -> String {
        if authoritative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return live
        }
        return authoritative
    }

    /// Puts each bookmark where it fell in the recording, not in a pile at the end.
    public static func merge(transcript: String, bookmarks: [TimeInterval], duration: TimeInterval) -> String {
        let base = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let missing = bookmarks.filter { !base.contains("— \(timer($0))") }.sorted()
        if missing.isEmpty { return transcript }
        if base.isEmpty {
            return missing.map { "— \(timer($0))" }.joined(separator: "\n") + "\n"
        }
        let words = base.split(separator: " ").map(String.init)
        let span = duration > 0 ? duration : 1
        var pieces: [String] = []
        var cursor = 0
        for (index, word) in words.enumerated() {
            while cursor < missing.count {
                let fraction = min(1, max(0, missing[cursor] / span))
                let at = min(words.count, Int((fraction * Double(words.count)).rounded(.down)))
                if at > index { break }
                if !pieces.isEmpty { pieces.append("\n\n") }
                pieces.append("— \(timer(missing[cursor]))")
                pieces.append("\n\n")
                cursor += 1
            }
            if index > 0, pieces.last != "\n\n" { pieces.append(" ") }
            pieces.append(word)
        }
        while cursor < missing.count {
            pieces.append("\n\n— \(timer(missing[cursor]))")
            cursor += 1
        }
        return pieces.joined()
    }
}
