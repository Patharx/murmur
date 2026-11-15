import Foundation
import XCTest
@testable import MurmurCore

final class NotebookTests: XCTestCase {
    func testSlugIsASCIIAndCapped() {
        XCTAssertEqual(
            NoteFilename.slug(from: "My father's garden, and the thing about rows"),
            "my-fathers-garden-and-the-thing-about-ro"
        )
        XCTAssertEqual(NoteFilename.slug(from: "Hello"), "hello")
        XCTAssertEqual(NoteFilename.slug(from: "   "), "note")
        XCTAssertEqual(NoteFilename.slug(from: "Café au lait"), "cafe-au-lait")
        XCTAssertLessThanOrEqual(NoteFilename.slug(from: String(repeating: "word ", count: 30)).count, 40)
    }

    func testBasenameUsesTheTimestampWallClock() {
        let stamp = NoteTimestamp(date: Date(timeIntervalSince1970: 0), text: "2026-08-06T07:42:11+01:00")
        XCTAssertEqual(
            NoteFilename.basename(created: stamp, title: "Hello"),
            "2026-08-06-0742-hello"
        )
    }

    func testCollisionAndEscape() throws {
        let root = try makeRoot()
        let layout = NotebookLayout(root: root)
        try layout.ensureSkeleton()
        for folder in NotebookLayout.defaultFolders {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(folder).path))
        }
        let stamp = NoteTimestamp(date: Date(timeIntervalSince1970: 0), text: "2026-08-06T07:42:11+01:00")
        let taken = root.appendingPathComponent("Walks/2026-08-06-0742-hello.md")
        try Data("x".utf8).write(to: taken)
        let allocated = try layout.allocateFilename(folder: "Walks", created: stamp, title: "Hello")
        XCTAssertEqual(allocated, "2026-08-06-0742-hello-2.md")
        let kept = try layout.allocateFilename(
            folder: "Walks",
            created: stamp,
            title: "Hello",
            excludingFilename: "2026-08-06-0742-hello.md"
        )
        XCTAssertEqual(kept, "2026-08-06-0742-hello.md")
        XCTAssertThrowsError(try layout.url(relativePath: "../secrets.md"))
        XCTAssertThrowsError(try layout.url(relativePath: "Walks/../../secrets.md"))
        XCTAssertEqual(NotebookLayout.safeFolder("../secrets"), NotebookLayout.oddsAndEnds)
        XCTAssertEqual(NotebookLayout.chipLabel(for: "Odds and ends"), "Odds & ends")
    }

    func testSaveSearchRenameRebuildAndEmptyDiscard() throws {
        let container = try makeRoot()
        let root = container.appendingPathComponent("Murmur", isDirectory: true)
        let database = container.appendingPathComponent("notes.sqlite")
        let notebook = try Notebook(root: root, databaseURL: database)
        let created = NoteTimestamp(date: Date(timeIntervalSince1970: 1_700_000_000), text: "2026-08-05T22:40:00+01:00")
        var letter = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
            created: created,
            modified: created,
            kind: .written,
            folder: "Written",
            title: "Draft of the letter",
            said: "Dear one."
        )
        let path = try notebook.save(letter, path: nil, now: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(path.hasPrefix("Written/"))
        XCTAssertEqual(try notebook.load(path: path).id, letter.id)
        var rows = try notebook.rows()
        XCTAssertEqual(rows.map(\.id), [letter.id])
        XCTAssertTrue(rows[0].onPhoneOnly)

        try notebook.markSynced(id: letter.id, syncedMtime: rows[0].localMtime)
        XCTAssertFalse(try XCTUnwrap(notebook.row(id: letter.id)).onPhoneOnly)

        letter.said = "Dear one. The garden was quiet."
        let edited = try notebook.save(letter, path: path, now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(edited, path)
        XCTAssertTrue(try XCTUnwrap(notebook.row(id: letter.id)).onPhoneOnly)
        XCTAssertEqual(try notebook.search("garden").map(\.id), [letter.id])
        XCTAssertEqual(try notebook.search("zzz").count, 0)
        XCTAssertEqual(try notebook.search("\"").count, 0)

        letter.title = "A completely different title"
        let renamed = try notebook.save(letter, path: edited, now: Date(timeIntervalSince1970: 3_000))
        XCTAssertNotEqual(renamed, edited)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try notebook.layout.url(relativePath: edited).path))
        XCTAssertEqual(try notebook.load(path: renamed).id, letter.id)
        XCTAssertEqual(try notebook.rows().map(\.id), [letter.id])

        try notebook.markSynced(id: letter.id, syncedMtime: try XCTUnwrap(notebook.row(id: letter.id)).localMtime)
        try notebook.rebuildIndex()
        let rebuilt = try XCTUnwrap(notebook.row(id: letter.id))
        XCTAssertEqual(rebuilt.path, renamed)
        XCTAssertFalse(rebuilt.onPhoneOnly)

        let loose = root.appendingPathComponent("Walks/loose-page.md")
        try Data("no front matter here".utf8).write(to: loose)
        try notebook.rebuildIndex()
        let unparsed = try notebook.rows().first { $0.id.hasPrefix("unparsed:") }
        XCTAssertEqual(unparsed?.path, "Walks/loose-page.md")

        var blank = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FB0",
            created: created,
            modified: created,
            kind: .written,
            folder: "Written",
            title: "   ",
            said: "\n"
        )
        let blankPath = try notebook.save(blank, path: nil, now: Date(timeIntervalSince1970: 4_000))
        let audio = try notebook.layout.url(relativePath: "Written/leftover.m4a")
        try Data("audio".utf8).write(to: audio)
        XCTAssertTrue(try notebook.discardIfEmpty(path: blankPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertNil(try notebook.row(id: blank.id))

        var voice = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FB1",
            created: created,
            modified: created,
            kind: .voice,
            folder: "Walks",
            title: "Morning",
            said: "hello",
            audioFilename: "old.m4a",
            durationSeconds: 12
        )
        let voicePath = try notebook.save(voice, path: nil, now: Date(timeIntervalSince1970: 5_000))
        let voiceURL = try notebook.layout.url(relativePath: voicePath)
        let oldAudio = voiceURL.deletingLastPathComponent().appendingPathComponent("old.m4a")
        try Data("m4a".utf8).write(to: oldAudio)
        voice.title = "Morning after the rain"
        let moved = try notebook.save(voice, path: voicePath, now: Date(timeIntervalSince1970: 6_000))
        let movedDoc = try notebook.load(path: moved)
        XCTAssertEqual(movedDoc.id, voice.id)
        let newAudio = try notebook.layout.url(relativePath: (moved as NSString).deletingLastPathComponent + "/" + (movedDoc.audioFilename ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newAudio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldAudio.path))
        XCTAssertEqual(NotebookLayout.safeFolder("Secrets"), "Secrets")
        var escaped = letter
        escaped.id = "01ARZ3NDEKTSV4RRFFQ69G5FB2"
        escaped.folder = "../secrets"
        escaped.title = "Stay inside"
        let safePath = try notebook.save(escaped, path: nil, now: Date(timeIntervalSince1970: 7_000))
        XCTAssertTrue(safePath.hasPrefix("Odds and ends/"))
    }

    func testSchemaNamesTheArchitectureColumns() {
        let sql = NoteIndex.createTableSQL
        for column in ["id", "path", "drive_id", "drive_rev", "local_mtime", "synced_mtime", "title", "folder", "kind", "created", "duration", "has_summary", "body"] {
            XCTAssertTrue(sql.contains(column), column)
        }
        XCTAssertTrue(NoteIndex.createFTSSQL.contains("fts5"))
    }

    func testULIDRoundTripsItsTimestamp() {
        let date = Date(timeIntervalSince1970: 1_754_000_000)
        let id = ULID(timestamp: date, randomness: [UInt8](repeating: 7, count: 10))
        XCTAssertEqual(id.description.count, 26)
        XCTAssertNotNil(ULID(parsing: id.description))
        let decoded = id.timestamp
        XCTAssertEqual(decoded?.timeIntervalSince1970 ?? -1, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(ULID(timestamp: Date(timeIntervalSince1970: 0), randomness: [UInt8](repeating: 0, count: 10)).description, "00000000000000000000000000")
    }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class TodayAndListeningTests: XCTestCase {
    func testDateLabelAndHeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        let date = DateComponents(calendar: calendar, year: 2026, month: 8, day: 6, hour: 12).date!
        XCTAssertEqual(TodayCopy.dateLabel(for: date, calendar: calendar), "Thursday 6 August")

        XCTAssertEqual(TodayCopy.headline(notesFromToday: [], folder: nil), "You didn't write anything today.")
        XCTAssertEqual(TodayCopy.headline(notesFromToday: [], folder: "Walks"), "Nothing in Walks today.")
        XCTAssertEqual(
            TodayCopy.headline(notesFromToday: [TodayNote(folder: "Walks", threads: [])], folder: nil),
            "You wrote one note today."
        )
        let notes = [
            TodayNote(folder: "Walks", threads: ["Your father", "Writing"]),
            TodayNote(folder: "Walks", threads: ["Your father"]),
            TodayNote(folder: "Written", threads: ["Writing"]),
        ]
        XCTAssertEqual(
            TodayCopy.headline(notesFromToday: notes, folder: nil),
            "You wrote three notes today, two of them about Your father."
        )
        XCTAssertEqual(
            TodayCopy.headline(notesFromToday: notes, folder: "Walks"),
            "You wrote two notes in Walks today, two of them about Your father."
        )
    }

    func testListeningHelpersAndPalette() {
        XCTAssertEqual(ListeningText.timer(0), "0:00")
        XCTAssertEqual(ListeningText.timer(75), "1:15")
        XCTAssertEqual(ListeningText.timer(3661), "1:01:01")
        XCTAssertEqual(ListeningText.bookmarkMarker(at: 12.8), "\n\n— 0:12\n\n")
        XCTAssertEqual(ListeningText.reconcile(live: "live line", authoritative: "  "), "live line")
        XCTAssertEqual(ListeningText.reconcile(live: "live line", authoritative: "from the file"), "from the file")
        XCTAssertEqual(
            ListeningText.merge(transcript: "from the file", bookmarks: [12]),
            "from the file\n\n— 0:12\n"
        )
        XCTAssertEqual(WaveformMetrics.barCount, 40)
        XCTAssertEqual(WaveformMetrics.height(decibels: -160), 6)
        XCTAssertEqual(WaveformMetrics.height(decibels: 0), 68)
        XCTAssertEqual(CaptureFormat.bitRate, 32_000)
        XCTAssertEqual(CaptureFormat.channelCount, 1)
        XCTAssertEqual(CaptureFormat.fileExtension, "m4a")
        XCTAssertEqual(MurmurPalette.bg, MurmurRGB(red: 22 / 255, green: 24 / 255, blue: 38 / 255))
        XCTAssertEqual(MurmurPalette.accent, MurmurRGB(hex: 0x9184D9))
        let blob = MurmurCopy.allUserFacing.joined(separator: "\n").lowercased()
        for banned in ["cancel", "save", "recording", "summary", "insights", "dictate", "key points", "action item"] {
            XCTAssertFalse(blob.contains(banned), banned)
        }
    }
}
