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

    /// The file transcript replaces the live line, unless the file produced nothing.
    public static func reconcile(live: String, authoritative: String) -> String {
        if authoritative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return live
        }
        return authoritative
    }

    public static func merge(transcript: String, bookmarks: [TimeInterval]) -> String {
        let base = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = bookmarks.map { timer($0) }.filter { marker in
            !base.contains("— \(marker)")
        }
        if markers.isEmpty { return transcript }
        let lines = markers.map { "— \($0)" }.joined(separator: "\n")
        if base.isEmpty { return lines + "\n" }
        return base + "\n\n" + lines + "\n"
    }
}
