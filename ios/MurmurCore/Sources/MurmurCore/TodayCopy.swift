import Foundation

public struct TodayNote: Equatable, Sendable {
    public var folder: String
    public var threads: [String]

    public init(folder: String, threads: [String]) {
        self.folder = folder
        self.threads = threads
    }
}

public enum TodayCopy {
    public static func dateLabel(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }

    /// Truthful, and only about the notes from today. `folder` nil means the whole notebook.
    public static func headline(notesFromToday notes: [TodayNote], folder: String?) -> String {
        let filtered: [TodayNote]
        if let folder, !folder.isEmpty {
            filtered = notes.filter { $0.folder == folder }
        } else {
            filtered = notes
        }
        let count = filtered.count
        let place = folder.map { " in \($0)" } ?? ""
        if count == 0 {
            if let folder {
                return "Nothing in \(folder) today."
            }
            return "You didn't write anything today."
        }
        let wrote = "You wrote \(spell(count)) \(count == 1 ? "note" : "notes")\(place) today"
        if let thread = sharedThread(in: filtered) {
            return "\(wrote), \(spell(thread.count)) of them about \(thread.name)."
        }
        return wrote + "."
    }

    private static func sharedThread(in notes: [TodayNote]) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for note in notes {
            var seen = Set<String>()
            for thread in note.threads where seen.insert(thread).inserted {
                if counts[thread] == nil { order.append(thread) }
                counts[thread, default: 0] += 1
            }
        }
        let best = order.filter { (counts[$0] ?? 0) >= 2 }.max { left, right in
            let leftCount = counts[left] ?? 0
            let rightCount = counts[right] ?? 0
            if leftCount == rightCount {
                return order.firstIndex(of: left)! > order.firstIndex(of: right)!
            }
            return leftCount < rightCount
        }
        guard let best, let count = counts[best] else { return nil }
        return (best, count)
    }

    private static func spell(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        if count >= 0 && count < words.count { return words[count] }
        return String(count)
    }
}
