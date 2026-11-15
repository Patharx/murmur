import Foundation
import XCTest
@testable import MurmurCore

final class NotebookTests: XCTestCase {
    func testSlugIsASCIIAndCapped() {
        XCTAssertEqual(
            NoteFilename.slug(from: "My father's garden, and the thing about rows"),
            "fathers-garden"
        )
        XCTAssertEqual(NoteFilename.slug(from: "Hello"), "hello")
        XCTAssertEqual(NoteFilename.slug(from: "   "), "note")
        XCTAssertEqual(NoteFilename.slug(from: "Café au lait"), "cafe-au")
        XCTAssertEqual(NoteFilename.basename(created: NoteTimestamp(date: Date(timeIntervalSince1970: 0), text: "2026-08-06T07:42:11+01:00"), title: "My father's garden, and the thing about rows"), "2026-08-06-0742-fathers-garden")
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

    func testALaterClipKeepsTheEarlierAudioAndDriveIdentitySurvivesRebuild() throws {
        let container = try makeRoot()
        let root = container.appendingPathComponent("Murmur", isDirectory: true)
        let notebook = try Notebook(root: root, databaseURL: container.appendingPathComponent("notes.sqlite"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Unlabeled").path))
        let created = NoteTimestamp(date: Date(timeIntervalSince1970: 1_700_000_000), text: "2026-08-05T22:40:00+01:00")
        let source = container.appendingPathComponent("take.m4a")
        try Data("first".utf8).write(to: source)
        var note = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FC0",
            created: created,
            modified: created,
            kind: .voice,
            folder: "Walks",
            title: "Morning",
            said: "hello"
        )
        let path = try notebook.storeVoiceNote(note, audioSource: source, now: Date(timeIntervalSince1970: 5_000))
        XCTAssertTrue(path.hasPrefix("Unlabeled/"))
        let stored = try notebook.load(path: path)
        let firstAudio = try notebook.layout.url(relativePath: (path as NSString).deletingLastPathComponent + "/" + (stored.audioFilename ?? ""))
        XCTAssertEqual(try Data(contentsOf: firstAudio), Data("first".utf8))

        var row = try XCTUnwrap(notebook.row(id: note.id))
        row.driveId = "drive-1"
        row.driveRev = "rev-1"
        try notebook.index.upsert(row)
        try notebook.rebuildIndex()
        let rebuilt = try XCTUnwrap(notebook.row(id: note.id))
        XCTAssertEqual(rebuilt.driveId, "drive-1")
        XCTAssertEqual(rebuilt.driveRev, "rev-1")

        let second = container.appendingPathComponent("later.m4a")
        try Data("second".utf8).write(to: second)
        let modified = NoteTimestamp(date: Date(timeIntervalSince1970: 1_700_003_600), text: "2026-08-06T15:42:00+01:00")
        _ = try notebook.addRecording(id: note.id, source: second, addedAt: Date(timeIntervalSince1970: 1_754_000_000), liveText: "a later one", modified: modified)
        let after = try notebook.load(path: path)
        XCTAssertEqual(after.audioFiles.count, 2)
        XCTAssertEqual(try Data(contentsOf: firstAudio), Data("first".utf8))
        let extra = try notebook.layout.url(relativePath: (path as NSString).deletingLastPathComponent + "/" + after.audioFiles[1])
        XCTAssertEqual(try Data(contentsOf: extra), Data("second".utf8))
        XCTAssertTrue(after.said.contains("— Added"))
        XCTAssertTrue(after.said.contains("a later one"))
        let still = try XCTUnwrap(notebook.row(id: note.id))
        XCTAssertEqual(still.driveId, "drive-1")
        XCTAssertEqual(still.driveRev, "rev-1")
        note.said = "hello"
    }

    func testAFailedAudioMoveDoesNotPointTheNoteAtAMissingFile() throws {
        let container = try makeRoot()
        let root = container.appendingPathComponent("Murmur", isDirectory: true)
        let notebook = try Notebook(root: root, databaseURL: container.appendingPathComponent("notes.sqlite"))
        let created = NoteTimestamp(date: Date(timeIntervalSince1970: 1_700_000_000), text: "2026-08-05T22:40:00+01:00")
        let source = container.appendingPathComponent("take.m4a")
        try Data("first".utf8).write(to: source)
        let note = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FC1",
            created: created,
            modified: created,
            kind: .voice,
            folder: NotebookLayout.unlabeled,
            title: "Morning",
            said: "hello"
        )
        let path = try notebook.storeVoiceNote(note, audioSource: source, now: Date(timeIntervalSince1970: 5_000))
        let folder = (path as NSString).deletingLastPathComponent
        let audioName = try notebook.load(path: path).audioFilename ?? ""
        let blocker = try notebook.layout.url(relativePath: folder + "/" + audioName.replacingOccurrences(of: ".m4a", with: "-2.m4a"))
        // Occupy the name the renamed primary would take by saving a title whose slug collides after we plant a file.
        var renamed = try notebook.load(path: path)
        let nextBase = NoteFilename.basename(created: created, title: "Evening")
        let planted = try notebook.layout.url(relativePath: folder + "/" + nextBase + ".m4a")
        try Data("do-not-delete".utf8).write(to: planted)
        renamed.title = "Evening"
        XCTAssertThrowsError(try notebook.save(renamed, path: path, now: Date(timeIntervalSince1970: 6_000)))
        let original = try notebook.load(path: path)
        XCTAssertEqual(original.title, "Morning")
        let originalAudio = try notebook.layout.url(relativePath: folder + "/" + audioName)
        XCTAssertEqual(try Data(contentsOf: originalAudio), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: planted), Data("do-not-delete".utf8))
        _ = blocker
    }

    func testTranscriptApplyLeavesAnEditedNoteAndDoesNotRetitle() {
        let created = NoteTimestamp(date: Date(timeIntervalSince1970: 0), text: "2026-08-06T07:42:11+01:00")
        let note = NoteDocument(
            id: "01ARZ3NDEKTSV4RRFFQ69G5FC2",
            created: created,
            modified: created,
            kind: .voice,
            folder: NotebookLayout.unlabeled,
            title: "Morning",
            said: "live draft",
            audioFilename: "clip.m4a"
        )
        let applied = NoteEditing.applyingFileTranscript(
            to: note,
            liveDraft: "live draft",
            authoritative: "from the file",
            bookmarks: [1],
            duration: 4
        )
        XCTAssertEqual(applied?.title, "Morning")
        XCTAssertEqual(applied?.said.contains("from the file"), true)
        var edited = note
        edited.said = "I changed this"
        XCTAssertNil(NoteEditing.applyingFileTranscript(to: edited, liveDraft: "live draft", authoritative: "from the file", bookmarks: [], duration: 4))
        let replaced = NoteEditing.applyingClipTranscript(
            said: "hello\n\n— Added 3:42 PM\n\nlive words",
            marker: "— Added 3:42 PM",
            liveDraft: "live words",
            authoritative: "from the file"
        )
        XCTAssertEqual(replaced, "hello\n\n— Added 3:42 PM\n\nfrom the file")
        XCTAssertNil(NoteEditing.applyingClipTranscript(said: "hello\n\n— Added 3:42 PM\n\nI fixed it", marker: "— Added 3:42 PM", liveDraft: "live words", authoritative: "from the file"))
    }

    func testSilenceChunkerSplitsALongTakeAtTheQuietGap() {
        var windows: [LevelWindow] = []
        for step in 0..<180 {
            let time = Double(step) * 0.5
            let quiet = time >= 40 && time < 41
            windows.append(LevelWindow(time: time, rms: quiet ? 0.001 : 0.2))
        }
        let ranges = SilenceChunker.ranges(windows: windows, duration: 90)
        XCTAssertGreaterThan(ranges.count, 1)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertLessThanOrEqual(ranges[0].upperBound, 50)
        XCTAssertGreaterThanOrEqual(ranges[0].upperBound, 40)
        XCTAssertEqual(ranges.last?.upperBound, 90)
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
            ListeningText.merge(transcript: "from the file", bookmarks: [12], duration: 24),
            "from\n\n— 0:12\n\nthe file"
        )
        var zone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 6
        parts.hour = 15
        parts.minute = 42
        parts.timeZone = zone
        let added = Calendar(identifier: .gregorian).date(from: parts)!
        XCTAssertEqual(ListeningText.addedMarker(at: added, timeZone: zone), "— Added 3:42 PM")
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
