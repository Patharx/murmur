import Foundation

public enum NoteFilename {
    /// ASCII slug, at most 40 characters. Apostrophes are dropped so "father's" stays one word.
    public static func slug(from title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let stripped = folded.applyingTransform(.stripDiacritics, reverse: false) ?? folded
        let withoutApostrophes = stripped
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "`", with: "")
        var out = ""
        var pendingHyphen = false
        for scalar in withoutApostrophes.unicodeScalars {
            let isASCII = scalar.value < 128
            if isASCII && CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen, !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.append(Character(scalar).lowercased())
            } else if !out.isEmpty {
                pendingHyphen = true
            }
            if out.count >= 40 { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.count > 40 { out = String(out.prefix(40)) }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "note" : out
    }

    /// `YYYY-MM-DD-HHmm-<slug>`, with `-2`, `-3`, … when `collision` is greater than zero.
    public static func basename(created: NoteTimestamp, title: String, collision: Int = 0) -> String {
        let stamp = NoteTimestampParser.wallClock(created.text)
        let slug = slug(from: title)
        if collision <= 0 { return "\(stamp)-\(slug)" }
        return "\(stamp)-\(slug)-\(collision + 1)"
    }
}
