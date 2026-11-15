import Foundation

public enum NoteKind: String, Equatable, Sendable, CaseIterable {
    case voice
    case written
    case hybrid
    case recap
}

public enum NoteParseError: Error, Equatable {
    case missingFrontMatter
    case missingIdentifier
    case invalidTimestamp(String)
    case invalidKind(String)
    case invalidDuration(String)
}

struct FrontMatterBlock: Equatable, Sendable {
    /// Comment and blank lines that sit directly above the key.
    var leading: String
    var key: String?
    /// Leading plus the key and any continuation lines, including the trailing newline.
    var raw: String
}

struct BodyPiece: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case gist
        case said
    }

    var kind: Kind
    var text: String
}

struct CapturedNote: Equatable, Sendable {
    var id: String
    var createdText: String
    var modifiedText: String
    var kind: NoteKind
    var folder: String
    var audio: String?
    var duration: Int?
    var title: String
    var threads: [String]
    var summaryModel: String?
    var summaryAtText: String?
    var rangeStart: String?
    var rangeEnd: String?
    var gist: String?
    var said: String
}

public struct NoteDocument: Equatable, Sendable {
    public var id: String
    public var created: NoteTimestamp
    public var modified: NoteTimestamp
    public var kind: NoteKind
    public var folder: String
    public var audioFilename: String?
    public var durationSeconds: Int?
    public var title: String
    public var threads: [String]
    public var summaryModel: String?
    public var summaryAt: NoteTimestamp?
    public var rangeStart: String?
    public var rangeEnd: String?
    /// Trimmed text under `## The gist`. Nil when that section is absent.
    public var gist: String?
    /// Trimmed text under `## What you said`.
    public var said: String

    var frontBlocks: [FrontMatterBlock]
    var bodyPieces: [BodyPiece]
    var gistSectionRaw: String?
    var saidSectionRaw: String?
    var bodySource: String?
    var originalText: String?
    var captured: CapturedNote?

    public var hasSummary: Bool {
        guard let gist else { return false }
        return !gist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var unknownFrontMatter: String {
        frontBlocks.filter { block in
            guard let key = block.key else { return true }
            return !NoteCodec.knownKeys.contains(key)
        }.map(\.raw).joined()
    }

    public init(
        id: String,
        created: NoteTimestamp,
        modified: NoteTimestamp,
        kind: NoteKind,
        folder: String,
        title: String,
        said: String,
        audioFilename: String? = nil,
        durationSeconds: Int? = nil,
        threads: [String] = [],
        summaryModel: String? = nil,
        summaryAt: NoteTimestamp? = nil,
        rangeStart: String? = nil,
        rangeEnd: String? = nil,
        gist: String? = nil
    ) {
        self.id = id
        self.created = created
        self.modified = modified
        self.kind = kind
        self.folder = folder
        self.audioFilename = audioFilename
        self.durationSeconds = durationSeconds
        self.title = title
        self.threads = threads
        self.summaryModel = summaryModel
        self.summaryAt = summaryAt
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.gist = gist
        self.said = said
        self.frontBlocks = []
        self.bodyPieces = []
        self.gistSectionRaw = nil
        self.saidSectionRaw = nil
        self.bodySource = nil
        self.originalText = nil
        self.captured = nil
    }
}
