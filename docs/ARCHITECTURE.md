# Murmur — architecture

## 1. The decision, stated plainly

There is no application server. There is no user database. There is no account system of our own.

The user signs in with Google. The app reads and writes files in a folder in *their* Drive. That
folder is the sync boundary, the backup, and the export format simultaneously. If Murmur is deleted
from the App Store tomorrow, every user still has their complete notebook in a folder of .m4a and
.md files they can open in any text editor.

The single exception is a stateless proxy for the Claude API key, described in §7. It holds no data,
has no database, and could be reimplemented from scratch in an afternoon.

### What this buys

- No breach surface. We never hold anyone's journal.
- No hosting cost that scales with users.
- No sync protocol to invent. Drive's Changes API already solved it.
- Export, backup and cross-device sync are the same feature, built once.
- Deleting your account is deleting a folder.

### What this costs

- Drive's API is not a database. No queries, no transactions, no partial reads. Every design below
  works around this.
- Offline conflict resolution is our problem (§6).
- Rate limits are per-user but real (§5.4).
- The email digest becomes genuinely hard (§8).

## 2. Drive folder layout

Use a **visible folder in My Drive**, named `Murmur`. Do **not** use `appDataFolder`.

`appDataFolder` is the conventional choice for app state and is wrong here. It is hidden from the
user, not browsable, and not readable outside the app — which contradicts the central product
promise ("your notebook is still readable if Murmur disappears"). Use the visible folder and accept
that users can move things and break sync; §6.4 handles that.

```
Murmur/
  Walks/
    2026-08-06-0742-fathers-garden.m4a
    2026-08-06-0742-fathers-garden.md
  Reflections/
    2026-08-06-1831-bus-home.md
  Written/
    2026-08-05-2240-draft-of-the-letter.md
  Reading/
  Odds and ends/
  Recaps/
    weekly/2026-W32.md
  .murmur/
    index.json          # note id -> path, mtime, revision. The sync ledger.
    device-<uuid>.json  # per-device sync cursor (Drive changes pageToken)
```

Notes:

- **Folders in the app map 1:1 to folders in Drive.** This is the whole promise. Renaming a folder
  in the app renames it in Drive; renaming it in Drive is picked up on next sync.
- **Voice notes are an .m4a + .md pair sharing a basename.** The .md is the note; the .m4a is the
  audio. Written notes have no .m4a. Pairing is by basename, never by Drive file ID.
- **Filenames are `YYYY-MM-DD-HHmm-<slug>`.** Sortable, human-meaningful, collision-resistant.
  The slug is derived from the title, ASCII-only, max 40 chars. Filenames are *display*, not
  identity — see §3.
- `.murmur/` is a real folder (a leading dot does not hide anything in Drive, but it signals intent
  and sorts to the top). Users who delete it lose sync state, not data — the app can rebuild the
  index by walking the tree.

## 3. The note file format

A note is a Markdown file with YAML front matter. The front matter is the record; the body is the
note. This format is the API.

```markdown
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
```

Rules:

- **`id` is a ULID and is the only identity.** Not the filename, not the Drive file ID. Filenames
  change when titles change; Drive file IDs change when a user copies a file. The ULID survives
  both, is sortable by creation time, and can be generated offline.
- **`## The gist` and `## What you said` are structural.** The parser finds sections by these exact
  headings. If `## The gist` is absent the note is unsummarised. A user editing the file in a text
  editor and deleting that section is a legitimate way to request re-summarisation.
- **Everything the app knows lives in the file.** No app-only metadata. If it is not in the front
  matter it does not exist. This is what makes the folder a real export.
- Unknown front-matter keys are preserved verbatim on write. Future versions will add keys and old
  clients must not destroy them.

## 4. Local store — the actual database

Drive is the sync target. The device is the database. Never read from Drive to render UI.

- **Files on disk** in the app container, mirroring the Drive layout exactly. Same paths, same names.
  Sync becomes a directory diff, which is far easier to reason about and to debug.
- **SQLite index** (GRDB or raw SQLite; avoid Core Data — the object graph buys nothing here and
  fights the file-first model). One table:

```sql
CREATE TABLE notes (
  id           TEXT PRIMARY KEY,   -- ULID
  path         TEXT NOT NULL,      -- relative: "Walks/2026-08-06-0742-....md"
  drive_id     TEXT,               -- NULL until first upload
  drive_rev    TEXT,               -- Drive headRevisionId at last sync
  local_mtime  INTEGER NOT NULL,
  synced_mtime INTEGER,            -- NULL or < local_mtime => dirty
  title        TEXT,
  folder       TEXT,
  kind         TEXT,               -- 'voice' | 'written'
  created      INTEGER,
  duration     INTEGER,
  has_summary  INTEGER DEFAULT 0,
  body         TEXT                -- for FTS
);
CREATE VIRTUAL TABLE notes_fts USING fts5(title, body, content=notes, content_rowid=rowid);
```

  The index is a **cache, always rebuildable** by walking the files. Never let it become the only
  copy of anything. A "rebuild index" action in Settings that nukes and rewalks is the correct fix
  for a whole class of bugs and should exist from day one.

- **`synced_mtime < local_mtime` is the entire dirty-tracking mechanism.** This is what drives the
  "on phone · push up" chip in the UI and the "Push N notes up now" row in Settings.

### Writing is local and synchronous

Typing in the compose screen writes to the local file on a debounce (~800ms idle). The UI copy
promises "Kept on this iPhone as you type — no connection needed" and that must be literally true.
Upload happens later and never blocks the user.

## 5. Drive integration

### 5.1 Auth

Google Sign-In for iOS + `GTMAppAuth`. Request the **narrowest scope that works**:

- `drive.file` — access only to files the app created or the user explicitly opened.

Use `drive.file`, not `drive`. It covers everything Murmur does, requires no Google verification
review for restricted scopes, and is a genuinely honest permission prompt. The one cost: if a user
moves a file into the Murmur folder from elsewhere, the app cannot see it. Acceptable.

Store tokens in the Keychain with `kSecAttrAccessibleAfterFirstUnlock` so background sync works.

### 5.2 Reading changes

Do not list the folder tree on every sync. Use the Changes API:

1. First run: `changes.getStartPageToken`, store in `.murmur/device-<uuid>.json`.
2. Every sync: `changes.list(pageToken:)`, filtered to the Murmur folder subtree.
3. Persist `newStartPageToken` after successfully applying the batch — not before.

This is O(changes), not O(notes), and is what makes sync cheap for a user with 4,000 notes.

### 5.3 Writing

- Create: multipart upload (metadata + content in one request).
- Update: `files.update` with `If-Match: <drive_rev>`. A 412 means someone else changed it —
  go to §6.
- Audio: resumable upload for anything over ~5 MB. A 40-minute m4a at 32kbps mono is ~10 MB; a
  reliable resumable path is not optional.
- Always request `fields=id,headRevisionId,modifiedTime` and store the revision.

### 5.4 Rate limits and batching

Drive allows roughly 12,000 queries per 60s per user — generous, and not the constraint. The real
constraints are battery and cellular data. Therefore:

- Sync on: app foreground, app background (BGProcessingTask), and after a note is finished.
- **Never sync mid-recording.** Audio capture gets the radio to itself.
- Upload audio on Wi-Fi only by default, with a Settings toggle. A user recording an hour of walks
  a week on cellular will notice, and will blame the app rather than the setting they never saw.
- Coalesce: a note edited five times in a minute uploads once.

## 6. Conflicts

Two devices, or one device and a user editing the .md in Drive's web editor. Rare, but it will
happen and silent data loss here is unforgivable in a journal.

### 6.1 Detection

`If-Match` on `drive_rev`. A 412 is a conflict. That is the only detection mechanism needed.

### 6.2 Resolution — never lose text

**Do not last-writer-wins the body.** Resolve field by field:

- Front matter, scalar fields (`title`, `folder`): newest `modified` wins.
- `threads`: union.
- `## The gist`: regenerate rather than merge; it is derived data.
- `## What you said` (the body): **if both sides changed it, keep both.** Write the remote version
  into a sibling file `<basename>-conflict-<device>.md` and surface a quiet banner on the note:
  "This note was edited in two places. Both versions kept." Let the human resolve it.

Losing a paragraph of someone's journal to a merge algorithm is a worse failure than showing them
two files.

### 6.3 Deletes

Deleting in-app moves the Drive file to Drive's trash, not `files.delete`. Drive's trash is a
30-day undo we get for free. A remote delete (file appears trashed in the changes feed) removes it
locally, but **only after the local copy has been confirmed uploaded** — otherwise a user who
deletes on device A loses an unsynced edit from device B.

### 6.4 The user moved things

Users will drag files around in Drive. Handle it:

- File moved to a different folder in Drive → its `folder` front-matter field is now stale. The
  **folder location wins**; rewrite the front matter to match. The filesystem is the truth.
- File renamed in Drive → filename is display-only, `id` is unchanged, nothing breaks.
- `.md` deleted but `.m4a` remains → orphaned audio. Show it in a "Recovered audio" section and
  offer to re-transcribe. Never delete the audio.
- `.murmur/index.json` deleted → rebuild by walking the tree.

## 7. The Claude API key problem

**An API key cannot ship inside a mobile app.** The binary is extractable, and a key in a shipped
app is a key that will be found and used. This is not a theoretical risk; it is a routine one.

Three options, in order of preference:

### Option A — a stateless proxy (recommended)

A single serverless function (Cloudflare Worker, Deno Deploy, Lambda — any of them). It:

1. Verifies the Google ID token the app sends (standard JWKS verification against Google's keys).
2. Checks a per-`sub` rate limit held in a KV store with a 24h TTL.
3. Forwards the request body to `api.anthropic.com` with the real key from an env var.
4. Streams the response back.
5. **Logs nothing. Stores nothing. Has no database.**

~300 lines. It never persists note content — the request passes through memory and is gone. This is
the only piece of infrastructure in the product, and if it is breached the attacker gets an API key,
not anyone's journal. That is exactly the liability profile you asked for.

Rate limit generously — say 200 requests/user/day — and treat exceeding it as a bug report rather
than an attack.

### Option B — bring your own key

Settings gains an "Anthropic API key" field; the key lives in the Keychain and the app calls the API
directly. Zero infrastructure, zero cost to you, perfect privacy story.

This fits the open-source positioning well and costs almost nothing to build — but it is a real wall
for non-technical users, who are most of the intended audience. **Ship both.** Option A is the
default; Option B is a Settings row for people who would rather not route through you at all. Given
the repo is public, offering B is close to obligatory — it is what makes "run it yourself" true.

### Option C — on-device summarisation

Apple's on-device Foundation model can produce a serviceable summary with no network at all. It is
meaningfully weaker at the thing this product actually needs — noticing that four notes across a
week are the same worry, and saying so in a sentence that sounds like a person. Worth revisiting for
per-note summaries specifically, where the bar is lower; not for weekly recaps.

## 8. The email digest is CUT

It was the only feature that required server state — an email address, a schedule that fires when
the phone is off, and a mail provider. That is a database, a cron and a third party, reintroducing
the entire liability Drive was chosen to avoid, for a feature that duplicates something already in
the app.

**Do not build it.** No email address is ever collected. The weekly recap lands in
`Murmur/Recaps/weekly/` as a .md file and in the Read back tab; anyone who wants it elsewhere has
it in their own Drive already.

A "send this to myself" button via `MFMailComposeViewController` is acceptable if it is ever asked
for — it opens Mail with the text prefilled and the user hits send. No address stored, no server.
Not in v1.

The Sunday notification is a local `UNNotificationRequest` and needs nothing.

## 8a. Ask — retrieval runs on the device

The "ask your notes anything" feature must not become a reason to send the notebook anywhere.

- FTS5 (already built, §4) for lexical recall.
- `NLEmbedding` / `NLContextualEmbedding` from the NaturalLanguage framework for semantic re-ranking.
  On-device, free, no vector database, no service.
- Store embeddings in the SQLite index; regenerate on note change. They are a cache like everything
  else in that table.
- Send **only the top ~10 matched gists** to Claude, never the corpus. See CLAUDE_LAYER §3.6.

This keeps the privacy claim in §10 intact and keeps the per-question cost around two cents instead
of two dollars. It is the whole reason this feature is affordable.

**One question, one answer, no conversation history.** Do not build a chat thread. The product is a
notebook that answers, not an assistant that chats — the moment there is a message history it has
become the thing this app is defined against.

## 9. Transcription

- iOS 26's `SpeechAnalyzer` / `SpeechTranscriber` is the current API and is substantially better than
  `SFSpeechRecognizer` for long-form audio: no ~1-minute practical ceiling, better punctuation,
  designed for file-based batch work. Use it where available.
- Keep `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` as the fallback path, and
  chunk audio at silence boundaries if you need to support it.
- **Transcribe from the file after recording, not live**, even though the prototype shows live text.
  The live transcript in the recording screen is a *confidence display* — it tells the user the app
  is listening. The authoritative transcript is produced in a background task from the saved .m4a,
  where it can take its time and be much more accurate. Reconciling the two is invisible to the user
  if the note opens after processing.
- Record at 32 kbps mono AAC. Speech does not need more, and it keeps a 40-minute walk at ~10 MB.
- `AVAudioSession` category `.playAndRecord` with `.allowBluetooth`, and background audio in
  `UIBackgroundModes` — people will start a note and put the phone in a pocket.

## 10. Privacy — what the app can honestly claim

Write these on the onboarding screen only if all of them stay true:

- Audio never leaves the device unless the user enables Drive backup (and then it goes only to their
  own Drive).
- Transcription happens on the device.
- Note *text* is sent to Anthropic only for the read-back features the user turns on, and is not
  stored by the proxy.
- Searching and asking happen on the device; only the handful of notes a question actually matches
  are sent.
- No email address is collected. Ever.
- Murmur operates no database of user content.

## 11. Repo structure

```
murmur/
  ios/                    # SwiftUI app
    Murmur/
      Capture/            # AVAudioRecorder, SpeechAnalyzer
      Store/              # SQLite index, file layout, note parser/serialiser
      Sync/               # Drive client, changes feed, conflict resolution
      Intelligence/       # prompt construction, proxy client, scheduling, on-device retrieval
      Threads/            # thread index, arc generation, thread screen
      UI/                 # screens — see DESIGN_SPEC.md
  proxy/                  # the ~300-line stateless Claude proxy
  docs/
    FILE_FORMAT.md        # §3 of this document, published — it is a public contract
    PRIVACY.md
```

Publish `FILE_FORMAT.md` prominently. A documented, boring, plain-text format that other tools can
read is the most credible possible statement that you are not trying to trap anyone's notes — and it
is the strongest thing the open-source positioning has going for it.
