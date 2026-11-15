import Foundation

public enum NoteFilename {
    /// Words that don't earn a place in a short filename.
    public static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "for", "with",
        "at", "by", "from", "as", "into", "over", "after", "before", "about",
        "my", "your", "our", "their", "his", "her", "its", "it", "this", "that",
        "these", "those", "is", "am", "are", "was", "were", "be", "been", "being",
        "i", "we", "you", "they", "me", "us", "them",
    ]

    /// The first two meaningful words, ASCII, hyphenated. `fathers-garden`, not the whole title.
    public static func slug(from title: String) -> String {
        let words = meaningfulWords(from: title)
        let kept = words.prefix(2)
        if kept.isEmpty { return "note" }
        var slug = kept.joined(separator: "-")
        if slug.count > 40 { slug = String(slug.prefix(40)) }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "note" : slug
    }

    public static func meaningfulWords(from title: String) -> [String] {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let stripped = folded.applyingTransform(.stripDiacritics, reverse: false) ?? folded
        let plain = stripped
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "`", with: "")
        var words: [String] = []
        var current = ""
        for scalar in plain.unicodeScalars {
            let isASCII = scalar.value < 128 && CharacterSet.alphanumerics.contains(scalar)
            if isASCII {
                current.append(Character(scalar).lowercased())
            } else if !current.isEmpty {
                if !stopwords.contains(current) { words.append(current) }
                current = ""
            }
        }
        if !current.isEmpty, !stopwords.contains(current) { words.append(current) }
        return words
    }

    /// `YYYY-MM-DD-HHmm-<slug>`, with `-2`, `-3`, … when `collision` is greater than zero.
    public static func basename(created: NoteTimestamp, title: String, collision: Int = 0) -> String {
        let stamp = NoteTimestampParser.wallClock(created.text)
        let slug = slug(from: title)
        if collision <= 0 { return "\(stamp)-\(slug)" }
        return "\(stamp)-\(slug)-\(collision + 1)"
    }
}
