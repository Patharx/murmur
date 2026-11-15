import Foundation

/// A timestamp as it is written in front matter. The lexical form is kept so a
/// read-modify-write does not renumber someone's timezone.
public struct NoteTimestamp: Equatable, Sendable, Hashable {
    public var date: Date
    public var text: String

    public init(date: Date, text: String) {
        self.date = date
        self.text = text
    }

    public static func parse(_ text: String) throws -> NoteTimestamp {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = NoteTimestampParser.date(from: trimmed) else {
            throw NoteParseError.invalidTimestamp(trimmed)
        }
        return NoteTimestamp(date: date, text: trimmed)
    }
}

enum NoteTimestampParser {
    static func date(from text: String) -> Date? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?((?:Z|[+-]\d{2}:\d{2}))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        func piece(_ index: Int) -> String? {
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swift = Range(r, in: text) else { return nil }
            return String(text[swift])
        }

        guard
            let year = piece(1).flatMap(Int.init),
            let month = piece(2).flatMap(Int.init),
            let day = piece(3).flatMap(Int.init),
            let hour = piece(4).flatMap(Int.init),
            let minute = piece(5).flatMap(Int.init),
            let second = piece(6).flatMap(Int.init),
            let zone = piece(8)
        else { return nil }

        let offset: Int
        if zone == "Z" {
            offset = 0
        } else {
            let sign = zone.hasPrefix("-") ? -1 : 1
            let parts = zone.dropFirst().split(separator: ":")
            guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            offset = sign * (hours * 3600 + minutes * 60)
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: offset)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        if let fraction = piece(7) {
            let digits = String(fraction.prefix(9))
            let padded = digits.padding(toLength: 9, withPad: "0", startingAt: 0)
            components.nanosecond = Int(padded)
        }
        return components.date
    }

    /// Wall-clock stamp for filenames: `YYYY-MM-DD-HHmm`, read from the text rather than converted.
    static func wallClock(_ text: String) -> String {
        let pattern = #"^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let dateRange = Range(match.range(at: 1), in: text),
            let hourRange = Range(match.range(at: 2), in: text),
            let minuteRange = Range(match.range(at: 3), in: text)
        else { return "1970-01-01-0000" }
        return "\(text[dateRange])-\(text[hourRange])\(text[minuteRange])"
    }
}
