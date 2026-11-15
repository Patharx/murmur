import Foundation
import XCTest
@testable import MurmurCore

final class NoteRoundTripTests: XCTestCase {
    func testCanonicalVoiceNoteRoundTripsByteForByte() throws {
        let parsed = try NoteCodec.parse(Fixtures.canonicalVoice)
        XCTAssertEqual(parsed.id, "01J9F3ZK7M2QW8XN4V6B0PCTGD")
        XCTAssertEqual(parsed.kind, .voice)
        XCTAssertEqual(parsed.folder, "Walks")
        XCTAssertEqual(parsed.audioFilename, "2026-08-06-0742-fathers-garden.m4a")
        XCTAssertEqual(parsed.durationSeconds, 258)
        XCTAssertEqual(parsed.title, "My father's garden, and the thing about rows")
        XCTAssertEqual(parsed.threads, ["Your father", "Writing", "Inheritance"])
        XCTAssertEqual(parsed.summaryModel, "claude-haiku-4-5")
        XCTAssertEqual(parsed.created.text, "2026-08-06T07:42:11+01:00")
        XCTAssertEqual(parsed.modified.text, "2026-08-06T07:58:02+01:00")
        XCTAssertEqual(parsed.summaryAt?.text, "2026-08-06T07:59:40+01:00")
        XCTAssertTrue(parsed.gist?.contains("not agronomy — the form was the point.") == true)
        XCTAssertTrue(parsed.said.hasPrefix("Walking past the allotments"))
        XCTAssertEqual(NoteCodec.serialize(parsed), Fixtures.canonicalVoice)
        XCTAssertEqual(NoteCodec.serialize(try NoteCodec.parse(NoteCodec.serialize(parsed))), Fixtures.canonicalVoice)
    }

    func testUnknownFrontMatterSurvivesReadModifyWriteUntouched() throws {
        var note = try NoteCodec.parse(Fixtures.withUnknownKeys)
        note.title = "Hello there"
        note.said = "First paragraph.\n\nSecond paragraph.\nAnd a third."
        note.modified = NoteTimestamp(date: note.modified.date.addingTimeInterval(60), text: "2026-08-06T07:59:02+01:00")

        let written = NoteCodec.serialize(note)
        let again = try NoteCodec.parse(written)

        XCTAssertEqual(again.id, "01J9F3ZK7M2QW8XN4V6B0PCTGD")
        XCTAssertEqual(again.title, "Hello there")
        XCTAssertEqual(again.said, "First paragraph.\n\nSecond paragraph.\nAnd a third.")
        XCTAssertEqual(again.unknownFrontMatter, note.unknownFrontMatter)
        XCTAssertEqual(again.unknownFrontMatter, Fixtures.unknownBlock + "\n")
        XCTAssertTrue(written.contains(Fixtures.unknownBlock))
        XCTAssertTrue(written.contains("count: 01\n"))
        XCTAssertFalse(written.contains("count: 1\n"))
        XCTAssertEqual(
            NoteCodec.serialize(try NoteCodec.parse(written)).contains(Fixtures.unknownBlock),
            true
        )
    }

    func testChangingTheTitleLeavesEveryOtherLineAlone() throws {
        let note = try NoteCodec.parse(Fixtures.canonicalVoice)
        var edited = note
        edited.title = "Rows, still"
        let written = NoteCodec.serialize(edited)
        XCTAssertTrue(written.contains("title: Rows, still"))
        XCTAssertNotEqual(written, Fixtures.canonicalVoice)
        let originalLines = Fixtures.canonicalVoice.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let writtenLines = written.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(originalLines.count, writtenLines.count)
        for (left, right) in zip(originalLines, writtenLines) where left != right {
            XCTAssertEqual(right, "title: Rows, still")
            XCTAssertTrue(left.hasPrefix("title:"))
        }
        XCTAssertEqual(try NoteCodec.parse(written).id, note.id)
        XCTAssertEqual(try NoteCodec.parse(written).gist, note.gist)
    }

    func testMissingGistMeansUnsummarisedAndStaysAbsent() throws {
        let parsed = try NoteCodec.parse(Fixtures.writtenWithoutGist)
        XCTAssertNil(parsed.gist)
        XCTAssertFalse(parsed.hasSummary)
        XCTAssertEqual(parsed.kind, .written)
        XCTAssertNil(parsed.audioFilename)
        XCTAssertNil(parsed.durationSeconds)
        XCTAssertEqual(parsed.said, "First paragraph.\n\nSecond paragraph.")
        let written = NoteCodec.serialize(parsed)
        XCTAssertFalse(written.contains("## The gist"))
        XCTAssertNil(try NoteCodec.parse(written).gist)
        XCTAssertEqual(written, Fixtures.writtenWithoutGist)
    }

    func testRemovingTheGistDropsTheSectionAndKeepsTheRest() throws {
        var note = try NoteCodec.parse(Fixtures.canonicalVoice)
        note.gist = nil
        let written = NoteCodec.serialize(note)
        XCTAssertFalse(written.contains("## The gist"))
        XCTAssertTrue(written.contains("## What you said"))
        XCTAssertTrue(written.contains("Walking past the allotments"))
        XCTAssertEqual(try NoteCodec.parse(written).gist, nil)
        XCTAssertTrue(written.contains("summary_model: claude-haiku-4-5"))
    }

    func testHandWrittenSectionOutsideTheTwoHeadingsSurvivesAnEdit() throws {
        var note = try NoteCodec.parse(Fixtures.withExtraSection)
        note.said = "Hello there."
        let written = NoteCodec.serialize(note)
        XCTAssertTrue(written.contains("## A heading I wrote"))
        XCTAssertTrue(written.contains("Some words."))
        XCTAssertTrue(written.contains("Hello there."))
        XCTAssertEqual(try NoteCodec.parse(written).said, "Hello there.")
    }

    func testQuotedTitleAndThreadsWithCommasRoundTrip() throws {
        let parsed = try NoteCodec.parse(Fixtures.quotedAndCommas)
        XCTAssertEqual(parsed.title, "Note: a title")
        XCTAssertEqual(parsed.threads, ["One, two", "Writing"])
        XCTAssertEqual(parsed.kind, .hybrid)
        XCTAssertEqual(parsed.audioFilename, "clip.m4a")
        let written = NoteCodec.serialize(parsed)
        XCTAssertEqual(try NoteCodec.parse(written).title, "Note: a title")
        XCTAssertEqual(try NoteCodec.parse(written).threads, ["One, two", "Writing"])
        XCTAssertEqual(written, Fixtures.quotedAndCommas)
    }

    func testRecapKeysRoundTrip() throws {
        let parsed = try NoteCodec.parse(Fixtures.recap)
        XCTAssertEqual(parsed.kind, .recap)
        XCTAssertEqual(parsed.rangeStart, "2026-08-03")
        XCTAssertEqual(parsed.rangeEnd, "2026-08-09")
        XCTAssertEqual(NoteCodec.serialize(parsed), Fixtures.recap)
    }

    func testCarriageReturnsStillYieldTheValues() throws {
        let crlf = Fixtures.writtenWithoutGist.replacingOccurrences(of: "\n", with: "\r\n")
        let parsed = try NoteCodec.parse(crlf)
        XCTAssertEqual(parsed.title, "A letter")
        XCTAssertEqual(parsed.said, "First paragraph.\n\nSecond paragraph.")
    }

    func testMissingIdentifierIsAnErrorAndTheBodyIsNotInventedAway() {
        XCTAssertThrowsError(try NoteCodec.parse(Fixtures.missingID)) { error in
            XCTAssertEqual(error as? NoteParseError, .missingIdentifier)
        }
    }

    func testMissingFrontMatterIsAnError() {
        XCTAssertThrowsError(try NoteCodec.parse("Just a paragraph.\n")) { error in
            XCTAssertEqual(error as? NoteParseError, .missingFrontMatter)
        }
    }

    func testBlockStyleThreadsAreRead() throws {
        let parsed = try NoteCodec.parse(Fixtures.blockThreads)
        XCTAssertEqual(parsed.threads, ["Your father", "Writing"])
    }

    func testASecondRecordingRoundTripsWithoutDroppingTheFirst() throws {
        let original = """
        ---
        id: 01ARZ3NDEKTSV4RRFFQ69G5FAV
        created: 2026-08-05T22:40:00+01:00
        modified: 2026-08-06T15:42:00+01:00
        kind: hybrid
        folder: Written
        audio: 2026-08-05-2240-letter.m4a
        recordings: [2026-08-05-2240-letter.m4a, 2026-08-06-1542-letter.m4a]
        title: A letter
        ---

        ## What you said

        The first take.

        — Added 3:42 PM

        A later one.

        """
        let parsed = try NoteCodec.parse(original)
        XCTAssertEqual(parsed.audioFilename, "2026-08-05-2240-letter.m4a")
        XCTAssertEqual(parsed.audioFiles, ["2026-08-05-2240-letter.m4a", "2026-08-06-1542-letter.m4a"])
        XCTAssertEqual(NoteCodec.serialize(parsed), original)
        var edited = parsed
        edited.said = "The first take.\n\n— Added 3:42 PM\n\nA later one, kept."
        let written = NoteCodec.serialize(edited)
        XCTAssertTrue(written.contains("audio: 2026-08-05-2240-letter.m4a"))
        XCTAssertTrue(written.contains("recordings: [2026-08-05-2240-letter.m4a, 2026-08-06-1542-letter.m4a]"))
        XCTAssertEqual(try NoteCodec.parse(written).audioFiles.count, 2)
    }

    func testNewWrittenNoteSerializesWithoutAudioOrDuration() {
        let created = NoteTimestamp(date: Date(timeIntervalSince1970: 0), text: "2026-08-05T22:40:00+01:00")
        let note = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
            created: created,
            modified: created,
            kind: .written,
            folder: "Written",
            title: "Draft of the letter",
            said: "Dear one.\n\nI started this at midnight."
        )
        let text = NoteCodec.serialize(note)
        XCTAssertFalse(text.contains("audio:"))
        XCTAssertFalse(text.contains("duration:"))
        XCTAssertFalse(text.contains("## The gist"))
        XCTAssertTrue(text.contains("kind: written"))
        XCTAssertTrue(text.contains("Dear one.\n\nI started this at midnight."))
        XCTAssertEqual(try NoteCodec.parse(text).said, "Dear one.\n\nI started this at midnight.")
    }
}

enum Fixtures {
    static let unknownBlock = """
    # kept by another tool
    custom_flag: true
    nested:
      - one
      - two
    count: 01
    """

    static let canonicalVoice = """
    ---
    id: 01J9F3ZK7M2QW8XN4V6B0PCTGD
    created: 2026-08-06T07:42:11+01:00
    modified: 2026-08-06T07:58:02+01:00
    kind: voice
    folder: Walks
    audio: 2026-08-06-0742-fathers-garden.m4a
    duration: 258
    title: My father's garden, and the thing about rows
    threads: [Your father, Writing, Inheritance]
    summary_model: claude-haiku-4-5
    summary_at: 2026-08-06T07:59:40+01:00
    ---

    ## The gist

    - You worked out that your father's insistence on planting in rows was inherited practice,
      not agronomy — the form was the point.
    - You extended that to your own writing habits.

    ## What you said

    Walking past the allotments on Wren Street and it hit me why my father planted in rows...

    """

    static let withUnknownKeys = """
    ---
    id: 01J9F3ZK7M2QW8XN4V6B0PCTGD
    created: 2026-08-06T07:42:11+01:00
    modified: 2026-08-06T07:58:02+01:00
    kind: written
    folder: Written
    title: Hello
    # kept by another tool
    custom_flag: true
    nested:
      - one
      - two
    count: 01
    ---

    ## What you said

    First paragraph.

    Second paragraph.

    """

    static let writtenWithoutGist = """
    ---
    id: 01ARZ3NDEKTSV4RRFFQ69G5FAV
    created: 2026-08-05T22:40:00+01:00
    modified: 2026-08-05T22:40:00+01:00
    kind: written
    folder: Written
    title: A letter
    ---

    ## What you said

    First paragraph.

    Second paragraph.

    """

    static let withExtraSection = """
    ---
    id: 01ARZ3NDEKTSV4RRFFQ69G5FAV
    created: 2026-08-05T22:40:00+01:00
    modified: 2026-08-05T22:40:00+01:00
    kind: written
    folder: Written
    title: Aside
    ---

    ## A heading I wrote

    Some words.

    ## What you said

    Hello.

    """

    static let quotedAndCommas = """
    ---
    id: 01ARZ3NDEKTSV4RRFFQ69G5FAV
    created: 2026-08-05T22:40:00+01:00
    modified: 2026-08-05T22:40:00+01:00
    kind: hybrid
    folder: Reflections
    audio: clip.m4a
    title: "Note: a title"
    threads: ["One, two", Writing]
    ---

    ## What you said

    Said aloud, then typed.

    """

    static let recap = """
    ---
    id: 01ARZ3NDEKTSV4RRFFQ69G5FAV
    created: 2026-08-09T08:00:00+01:00
    modified: 2026-08-09T08:00:00+01:00
    kind: recap
    folder: Recaps
    title: The week
    range_start: 2026-08-03
    range_end: 2026-08-09
    ---

    ## What you said

    You kept coming back to the garden.

    """

    static let missingID = """
    ---
    created: 2026-08-05T22:40:00+01:00
    modified: 2026-08-05T22:40:00+01:00
    kind: written
    folder: Written
    title: No id
    ---

    ## What you said

    Still here.

    """

    static let blockThreads = """
    ---
    id: 01ARZ3NDEKTSV4RRFFQ69G5FAV
    created: 2026-08-05T22:40:00+01:00
    modified: 2026-08-05T22:40:00+01:00
    kind: written
    folder: Written
    title: Threads
    threads:
      - Your father
      - Writing
    ---

    ## What you said

    Hello.

    """
}
