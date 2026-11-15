import Foundation

public enum NoteCodec {
    static let knownKeys: Set<String> = [
        "id", "created", "modified", "kind", "folder", "audio", "recordings", "phone_only", "duration",
        "title", "threads", "summary_model", "summary_at", "range_start", "range_end",
    ]

    private static let keyOrder = [
        "id", "created", "modified", "kind", "folder", "audio", "recordings", "phone_only", "duration",
        "title", "threads", "summary_model", "summary_at", "range_start", "range_end",
    ]

    public static func parse(_ text: String) throws -> NoteDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let (front, body) = try split(normalized)
        let blocks = frontBlocks(from: front)
        var values: [String: FrontMatterBlock] = [:]
        for block in blocks {
            if let key = block.key {
                values[key] = block
            }
        }

        guard let idBlock = values["id"] else { throw NoteParseError.missingIdentifier }
        let id = scalar(from: idBlock)
        if id.isEmpty { throw NoteParseError.missingIdentifier }

        guard let createdBlock = values["created"] else {
            throw NoteParseError.invalidTimestamp("created")
        }
        let created = try NoteTimestamp.parse(scalar(from: createdBlock))
        guard let modifiedBlock = values["modified"] else {
            throw NoteParseError.invalidTimestamp("modified")
        }
        let modified = try NoteTimestamp.parse(scalar(from: modifiedBlock))

        let recordings = values["recordings"].map { parseThreads(from: $0) } ?? []
        let phoneOnly = values["phone_only"].map { truthy(scalar(from: $0)) } ?? false
        var audio = values["audio"].map { scalar(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        if audio == nil { audio = recordings.first }
        let kind = try parseKind(values["kind"].map { scalar(from: $0) }, audio: audio)
        let folderScalar = values["folder"].map { scalar(from: $0) } ?? ""
        let folder = folderScalar.isEmpty ? "Odds and ends" : folderScalar
        let title = values["title"].map { scalar(from: $0) } ?? ""
        let threads = values["threads"].map { parseThreads(from: $0) } ?? []
        let duration = try values["duration"].map { try parseDuration(scalar(from: $0)) } ?? nil
        let summaryModel = values["summary_model"].map { scalar(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let summaryAt = try values["summary_at"].map { try NoteTimestamp.parse(scalar(from: $0)) }
        let rangeStart = values["range_start"].map { scalar(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let rangeEnd = values["range_end"].map { scalar(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }

        let pieces = bodyPieces(from: body)
        let gistRaw = pieces.first { $0.kind == .gist }?.text
        let saidRaw = pieces.first { $0.kind == .said }?.text
        let gist = gistRaw.map(trimOuterNewlines)
        let said = saidRaw.map(trimOuterNewlines) ?? ""

        var note = NoteDocument(
            id: id,
            created: created,
            modified: modified,
            kind: kind,
            folder: folder,
            title: title,
            said: said,
            audioFilename: audio,
            recordings: recordings.count > 1 ? recordings : [],
            phoneOnly: phoneOnly,
            durationSeconds: duration,
            threads: threads,
            summaryModel: summaryModel,
            summaryAt: summaryAt,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            gist: gist
        )
        note.frontBlocks = blocks
        note.bodyPieces = pieces
        note.gistSectionRaw = gistRaw.map { "## The gist\n" + $0 }
        note.saidSectionRaw = saidRaw.map { "## What you said\n" + $0 }
        note.bodySource = body
        note.originalText = normalized.hasSuffix("\n") || normalized.isEmpty ? normalized : normalized + "\n"
        note.captured = CapturedNote(
            id: id,
            createdText: created.text,
            modifiedText: modified.text,
            kind: kind,
            folder: folder,
            audio: audio,
            recordings: recordings.count > 1 ? recordings : [],
            phoneOnly: phoneOnly,
            duration: duration,
            title: title,
            threads: threads,
            summaryModel: summaryModel,
            summaryAtText: summaryAt?.text,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            gist: gist,
            said: said
        )
        return note
    }

    public static func serialize(_ note: NoteDocument) -> String {
        if let original = note.originalText, isUnchanged(note) {
            return original.hasSuffix("\n") ? original : original + "\n"
        }
        let front = renderFront(note)
        var body = renderBody(note)
        if !body.hasPrefix("\n") && !body.isEmpty {
            body = "\n" + body
        }
        if body.isEmpty {
            body = "\n"
        }
        var text = "---\n\(front)---\n\(body)"
        if !text.hasSuffix("\n") {
            text += "\n"
        }
        return text
    }

    private static func isUnchanged(_ note: NoteDocument) -> Bool {
        guard let snap = note.captured else { return false }
        return note.id == snap.id
            && note.created.text == snap.createdText
            && note.modified.text == snap.modifiedText
            && note.kind == snap.kind
            && note.folder == snap.folder
            && note.audioFilename == snap.audio
            && note.recordings == snap.recordings
            && note.phoneOnly == snap.phoneOnly
            && note.durationSeconds == snap.duration
            && note.title == snap.title
            && note.threads == snap.threads
            && note.summaryModel == snap.summaryModel
            && note.summaryAt?.text == snap.summaryAtText
            && note.rangeStart == snap.rangeStart
            && note.rangeEnd == snap.rangeEnd
            && note.gist == snap.gist
            && note.said == snap.said
    }

    private static func renderFront(_ note: NoteDocument) -> String {
        if note.frontBlocks.isEmpty {
            return canonicalFront(note)
        }
        var seen = Set<String>()
        var out = ""
        for block in note.frontBlocks {
            guard let key = block.key else {
                out += block.raw
                continue
            }
            if !knownKeys.contains(key) {
                out += block.raw
                continue
            }
            seen.insert(key)
            if fieldUnchanged(key, note: note) {
                out += block.raw
            } else if shouldEmit(key, note: note) {
                out += block.leading + formatted(key, note: note) + "\n"
            }
        }
        for key in keyOrder where !seen.contains(key) && shouldEmit(key, note: note) {
            out += formatted(key, note: note) + "\n"
        }
        return out
    }

    private static func fieldUnchanged(_ key: String, note: NoteDocument) -> Bool {
        guard let snap = note.captured else { return false }
        switch key {
        case "id": return note.id == snap.id
        case "created": return note.created.text == snap.createdText
        case "modified": return note.modified.text == snap.modifiedText
        case "kind": return note.kind == snap.kind
        case "folder": return note.folder == snap.folder
        case "audio": return note.audioFilename == snap.audio
        case "recordings": return note.recordings == snap.recordings
        case "phone_only": return note.phoneOnly == snap.phoneOnly
        case "duration": return note.durationSeconds == snap.duration
        case "title": return note.title == snap.title
        case "threads": return note.threads == snap.threads
        case "summary_model": return note.summaryModel == snap.summaryModel
        case "summary_at": return note.summaryAt?.text == snap.summaryAtText
        case "range_start": return note.rangeStart == snap.rangeStart
        case "range_end": return note.rangeEnd == snap.rangeEnd
        default: return false
        }
    }

    private static func shouldEmit(_ key: String, note: NoteDocument) -> Bool {
        switch key {
        case "id", "created", "modified", "kind", "folder", "title":
            return true
        case "audio":
            return note.audioFilename != nil
        case "recordings":
            return note.recordings.count > 1
        case "phone_only":
            return note.phoneOnly
        case "duration":
            return note.durationSeconds != nil
        case "threads":
            return !note.threads.isEmpty
        case "summary_model":
            return note.summaryModel != nil
        case "summary_at":
            return note.summaryAt != nil
        case "range_start":
            return note.rangeStart != nil
        case "range_end":
            return note.rangeEnd != nil
        default:
            return false
        }
    }

    private static func canonicalFront(_ note: NoteDocument) -> String {
        keyOrder.filter { shouldEmit($0, note: note) }.map { formatted($0, note: note) + "\n" }.joined()
    }

    private static func formatted(_ key: String, note: NoteDocument) -> String {
        switch key {
        case "id": return "id: \(note.id)"
        case "created": return "created: \(note.created.text)"
        case "modified": return "modified: \(note.modified.text)"
        case "kind": return "kind: \(note.kind.rawValue)"
        case "folder": return "folder: \(yamlScalar(note.folder))"
        case "audio": return "audio: \(yamlScalar(note.audioFilename ?? ""))"
        case "recordings": return "recordings: \(yamlFlow(note.recordings))"
        case "phone_only": return "phone_only: true"
        case "duration": return "duration: \(note.durationSeconds ?? 0)"
        case "title": return "title: \(yamlScalar(note.title))"
        case "threads": return "threads: \(yamlFlow(note.threads))"
        case "summary_model": return "summary_model: \(yamlScalar(note.summaryModel ?? ""))"
        case "summary_at": return "summary_at: \(note.summaryAt?.text ?? "")"
        case "range_start": return "range_start: \(yamlScalar(note.rangeStart ?? ""))"
        case "range_end": return "range_end: \(yamlScalar(note.rangeEnd ?? ""))"
        default: return "\(key):"
        }
    }

    private static func renderBody(_ note: NoteDocument) -> String {
        let gistSame = note.gist == note.captured?.gist
        let saidSame = note.said == note.captured?.said
        if gistSame && saidSame, let body = note.bodySource {
            return body
        }
        if note.bodyPieces.isEmpty {
            return canonicalBody(note)
        }
        var out = ""
        var wroteGist = false
        var wroteSaid = false
        for piece in note.bodyPieces {
            switch piece.kind {
            case .text:
                out += piece.text
            case .gist:
                wroteGist = true
                if let gist = note.gist {
                    if gistSame, let raw = note.gistSectionRaw {
                        out += raw
                    } else {
                        out += "## The gist\n\n\(gist)\n\n"
                    }
                }
            case .said:
                wroteSaid = true
                if saidSame, let raw = note.saidSectionRaw {
                    out += raw
                } else if !note.said.isEmpty || note.captured?.said.isEmpty == false {
                    out += "## What you said\n\n\(note.said)\n"
                }
            }
        }
        if note.gist != nil && !wroteGist {
            out += "## The gist\n\n\(note.gist ?? "")\n\n"
        }
        if !wroteSaid && !note.said.isEmpty {
            out += "## What you said\n\n\(note.said)\n"
        }
        return out
    }

    private static func canonicalBody(_ note: NoteDocument) -> String {
        var parts = ""
        if let gist = note.gist {
            parts += "## The gist\n\n\(gist)\n\n"
        }
        if !note.said.isEmpty || note.kind == .voice || note.kind == .hybrid {
            parts += "## What you said\n\n\(note.said)\n"
        } else if !note.said.isEmpty {
            parts += "## What you said\n\n\(note.said)\n"
        }
        if parts.isEmpty && !note.said.isEmpty {
            parts = "## What you said\n\n\(note.said)\n"
        }
        if !note.said.isEmpty && !parts.contains("## What you said") {
            parts += "## What you said\n\n\(note.said)\n"
        }
        if parts.isEmpty {
            parts = "## What you said\n\n\(note.said)\n"
        }
        return "\n" + parts
    }

    private static func split(_ text: String) throws -> (front: String, body: String) {
        let lines = keepingNewlines(text)
        guard let first = lines.first, strippingNewline(first) == "---" else {
            throw NoteParseError.missingFrontMatter
        }
        var index = 1
        var front = ""
        var closed = false
        while index < lines.count {
            if strippingNewline(lines[index]) == "---" {
                closed = true
                index += 1
                break
            }
            front += lines[index]
            index += 1
        }
        guard closed else { throw NoteParseError.missingFrontMatter }
        return (front, lines[index...].joined())
    }

    private static func frontBlocks(from front: String) -> [FrontMatterBlock] {
        let lines = keepingNewlines(front)
        var index = 0
        var leading = ""
        var blocks: [FrontMatterBlock] = []
        while index < lines.count {
            let line = lines[index]
            if isKeyLine(line) {
                let key = keyName(line)
                let blockLeading = leading
                var raw = leading + line
                leading = ""
                index += 1
                let literal = isLiteralScalar(line)
                while index < lines.count {
                    let next = lines[index]
                    if isKeyLine(next) { break }
                    if literal || isIndented(next) {
                        raw += next
                        index += 1
                        continue
                    }
                    break
                }
                blocks.append(FrontMatterBlock(leading: blockLeading, key: key, raw: raw))
            } else {
                leading += line
                index += 1
            }
        }
        if !leading.isEmpty {
            blocks.append(FrontMatterBlock(leading: "", key: nil, raw: leading))
        }
        return blocks
    }

    private static func bodyPieces(from body: String) -> [BodyPiece] {
        let lines = keepingNewlines(body)
        var pieces: [BodyPiece] = []
        var buffer = ""
        var mode: BodyPiece.Kind = .text

        func flush() {
            if mode == .text {
                if !buffer.isEmpty {
                    pieces.append(BodyPiece(kind: .text, text: buffer))
                }
            } else {
                pieces.append(BodyPiece(kind: mode, text: buffer))
            }
            buffer = ""
        }

        for line in lines {
            let bare = strippingNewline(line)
            if bare == "## The gist" || bare == "## What you said" {
                flush()
                mode = bare == "## The gist" ? .gist : .said
                continue
            }
            buffer += line
        }
        flush()
        return pieces
    }

    private static func truthy(_ raw: String) -> Bool {
        ["true", "yes", "1"].contains(raw.lowercased())
    }

    private static func parseKind(_ raw: String?, audio: String?) throws -> NoteKind {
        guard let raw, !raw.isEmpty else {
            return audio == nil ? .written : .voice
        }
        guard let kind = NoteKind(rawValue: raw) else {
            throw NoteParseError.invalidKind(raw)
        }
        return kind
    }

    private static func parseDuration(_ raw: String) throws -> Int {
        guard let value = Int(raw) else { throw NoteParseError.invalidDuration(raw) }
        return value
    }

    private static func parseThreads(from block: FrontMatterBlock) -> [String] {
        let content = String(block.raw.dropFirst(block.leading.count))
        let lines = keepingNewlines(content)
        guard let first = lines.first else { return [] }
        let value = scalarText(afterKey: first)
        if value.hasPrefix("[") {
            return parseFlow(value)
        }
        if value.isEmpty {
            return lines.dropFirst().compactMap { line in
                let trimmed = strippingNewline(line).trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") else { return nil }
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return [value]
    }

    private static func scalar(from block: FrontMatterBlock) -> String {
        let content = String(block.raw.dropFirst(block.leading.count))
        guard let first = keepingNewlines(content).first else { return "" }
        return scalarText(afterKey: first)
    }

    private static func scalarText(afterKey line: String) -> String {
        let bare = strippingNewline(line)
        guard let colon = bare.firstIndex(of: ":") else { return "" }
        var value = String(bare[bare.index(after: colon)...])
        if !value.trimmingCharacters(in: .whitespaces).hasPrefix("\"")
            && !value.trimmingCharacters(in: .whitespaces).hasPrefix("'")
            && !value.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound])
            }
        }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return unescape(String(value.dropFirst().dropLast()))
        }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value
    }

    private static func parseFlow(_ raw: String) -> [String] {
        guard raw.hasPrefix("[") else { return [] }
        var inner = raw
        if inner.hasSuffix("]") { inner.removeLast() }
        inner.removeFirst()
        var items: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false
        for character in inner {
            if character == "\"" && !inSingle {
                inDouble.toggle()
                current.append(character)
            } else if character == "'" && !inDouble {
                inSingle.toggle()
                current.append(character)
            } else if character == "," && !inDouble && !inSingle {
                items.append(cleanFlowItem(current))
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty || !items.isEmpty {
            let cleaned = cleanFlowItem(current)
            if !cleaned.isEmpty || !items.isEmpty && current.contains("\"") {
                items.append(cleaned)
            }
        }
        return items.filter { !$0.isEmpty || raw.contains("\"\"") }
    }

    private static func cleanFlowItem(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return unescape(String(value.dropFirst().dropLast()))
        }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value
    }

    private static func unescape(_ value: String) -> String {
        var out = ""
        var escaping = false
        for character in value {
            if escaping {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                out.append(character)
            }
        }
        if escaping { out.append("\\") }
        return out
    }

    static func yamlScalar(_ value: String) -> String {
        if value.isEmpty { return "\"\"" }
        let reserved: Set<String> = ["true", "false", "null", "yes", "no", "~"]
        let needsQuotes =
            reserved.contains(value.lowercased())
            || value.contains(":")
            || value.contains("#")
            || value.contains("\"")
            || value.contains("'")
            || value.contains("\n")
            || value.contains("[")
            || value.contains("]")
            || value.contains("{")
            || value.contains("}")
            || value.hasPrefix(" ")
            || value.hasSuffix(" ")
            || value.hasPrefix("&")
            || value.hasPrefix("*")
            || value.hasPrefix("!")
            || value.hasPrefix("|")
            || value.hasPrefix(">")
            || Int(value) != nil
            || Double(value) != nil
        if !needsQuotes { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func yamlFlow(_ items: [String]) -> String {
        let parts = items.map { item -> String in
            if item.contains(",") || item.contains(":") || item.contains("#") || item.contains("\"")
                || item.contains("[") || item.contains("]") || item.hasPrefix(" ") || item.hasSuffix(" ") {
                return yamlScalar(item)
            }
            return item
        }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    private static func isKeyLine(_ line: String) -> Bool {
        let bare = strippingNewline(line)
        guard let first = bare.first, first != " ", first != "\t", first != "-" else { return false }
        guard let colon = bare.firstIndex(of: ":") else { return false }
        let key = bare[..<colon]
        guard let keyFirst = key.first, keyFirst.isLetter || keyFirst == "_" else { return false }
        return key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    private static func keyName(_ line: String) -> String {
        let bare = strippingNewline(line)
        guard let colon = bare.firstIndex(of: ":") else { return "" }
        return String(bare[..<colon])
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t")
    }

    private static func isLiteralScalar(_ line: String) -> Bool {
        let value = scalarText(afterKey: line)
        return value == "|" || value == ">" || value.hasPrefix("|") || value.hasPrefix(">")
    }

    private static func strippingNewline(_ line: String) -> String {
        if line.hasSuffix("\n") { return String(line.dropLast()) }
        return line
    }

    private static func trimOuterNewlines(_ text: String) -> String {
        var value = text
        while value.hasPrefix("\n") { value.removeFirst() }
        while value.hasSuffix("\n") { value.removeLast() }
        return value
    }

    private static func keepingNewlines(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "\n" {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
