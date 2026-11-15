import Foundation

public struct LevelWindow: Equatable, Sendable {
    public var time: TimeInterval
    public var rms: Float

    public init(time: TimeInterval, rms: Float) {
        self.time = time
        self.rms = rms
    }
}

/// Splits a long recording at quiet stretches so on-device recognition can take it a minute at a time.
public enum SilenceChunker {
    public static func ranges(
        windows: [LevelWindow],
        duration: TimeInterval,
        silenceRMS: Float = 0.02,
        minSilence: TimeInterval = 0.3,
        maxChunk: TimeInterval = 50,
        minChunk: TimeInterval = 10
    ) -> [Range<TimeInterval>] {
        guard duration > 0 else { return [] }
        if duration <= maxChunk { return [0..<duration] }
        let ordered = windows.sorted { $0.time < $1.time }
        var ranges: [Range<TimeInterval>] = []
        var start: TimeInterval = 0
        while duration - start > maxChunk {
            let limit = start + maxChunk
            let earliest = start + minChunk
            let split = silenceEnd(in: ordered, from: earliest, to: limit, threshold: silenceRMS, minSilence: minSilence) ?? limit
            ranges.append(start..<min(split, duration))
            start = min(split, duration)
        }
        if start < duration {
            ranges.append(start..<duration)
        }
        return ranges
    }

    private static func silenceEnd(
        in windows: [LevelWindow],
        from earliest: TimeInterval,
        to limit: TimeInterval,
        threshold: Float,
        minSilence: TimeInterval
    ) -> TimeInterval? {
        var quietSince: TimeInterval?
        var lastQuiet: TimeInterval?
        for window in windows where window.time >= earliest && window.time <= limit {
            if window.rms <= threshold {
                if quietSince == nil { quietSince = window.time }
                lastQuiet = window.time
                if let quietSince, window.time - quietSince >= minSilence {
                    return window.time
                }
            } else {
                quietSince = nil
            }
        }
        if let quietSince, let lastQuiet, lastQuiet - quietSince >= minSilence {
            return lastQuiet
        }
        return nil
    }
}
