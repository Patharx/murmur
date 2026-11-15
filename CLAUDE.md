# Murmur — working agreement for Claude Code

Read this first, then `docs/ARCHITECTURE.md`. Both are binding.

## What this is

A personal voice + written notebook for iPhone. Not a work tool. No meetings, no action items, no
productivity metrics. If a change would make sense in a meeting-notes app, it is probably wrong here.

## The four rules that decide most arguments

1. **Drive is the database.** No application server, no user database, no accounts of our own. The
   only backend is a stateless key proxy that stores nothing. If a feature needs server state, the
   feature is wrong — say so instead of building the server.
2. **The device is the source of truth.** Everything is written locally first and synced after.
   No UI ever blocks on the network. "Kept on this iPhone as you type" is literal.
3. **Never lose text.** This is someone's journal. On any conflict, keep both versions and let the
   human resolve it. A merge algorithm that eats a paragraph is worse than two files.
4. **The vocabulary is the product.** "Listening" not "Recording". "Read back" not "Summary".
   "The gist" not "Key points". "Never mind" not "Cancel". "Keep" not "Save". "Say it instead" not
   "Dictate". Do not normalise these to standard iOS wording.

## Stack

- SwiftUI, iOS 17+ minimum, iOS 26 APIs used where available with fallbacks.
- SQLite via GRDB. **Not Core Data** — the object graph fights the file-first model.
- No third-party dependencies beyond GRDB and Google Sign-In. Justify any addition in the PR.
- Files on disk mirror the Drive layout exactly, so sync is a directory diff.

## Layout

```
ios/Murmur/
  Capture/        AVAudioRecorder, SpeechAnalyzer, quick-capture App Intents
  Store/          note parser/serialiser, SQLite index, file layout
  Sync/           Drive client, changes feed, conflict resolution
  Intelligence/   prompts, proxy client, scheduling, on-device retrieval
  Threads/        thread index, arc generation
  UI/             screens — build to docs/DESIGN_SPEC.md
proxy/            the stateless Claude proxy (~300 lines)
docs/             ARCHITECTURE, CLAUDE_LAYER, DESIGN_SPEC, FILE_FORMAT, PRIVACY
design/           Murmur.dc.html — the interactive design reference
```

## Build order — do not reorder

1. Local store + capture + transcription. No Drive, no Claude.
2. Quick capture (App Intent, Action Button, Lock Screen, Siri).
3. Drive sync.
4. Note gists, with the short-note gate.
5. Threads.
6. Weekly recap.
7. Ask.

Steps 1–2 are a complete, useful app. Ship them to yourself and live with them for a month before
step 3. You will learn more from that month than from any planning.

## Design work

`docs/DESIGN_SPEC.md` is high-fidelity and final: every colour, size, weight and string is
specified. `design/Murmur.dc.html` is an interactive HTML reference — **open it in a browser and
tap through it**, but do not port it. It is a design artifact, not source. Rebuild natively.

Where the HTML and the spec disagree, the spec wins.

## Things that are settled — do not reopen without asking

- No daily recap. Weekly only.
- No email digest. No email address is ever collected.
- No tags, no streaks, no sharing, no collaboration.
- Ask is one question, one answer. **No conversation history, no follow-up field.** The moment
  there is a message thread it has become a chatbot, which is the thing this app is defined against.
- No gist when a note is under 80 words or under one minute of audio. Either one is enough.
- Dropbox/OneDrive are designed but not in v1.

## Testing

- The note parser/serialiser round-trip is the highest-value test in the codebase. Unknown YAML keys
  must survive a read-modify-write untouched.
- Conflict resolution needs tests for: both sides edited, remote deleted while local dirty, file
  moved between folders in Drive, .md deleted with .m4a surviving.
- Snapshot-test the empty states. They are easy to break and they are the first thing a new user
  sees.

## Tone check for any user-facing string

Would a close friend say it? Is it second person and past tense? Does it avoid praising the user for
using the app? If any answer is no, rewrite it. The banned-phrase list in `docs/CLAUDE_LAYER.md` §3.1
applies to interface copy as well as model output.
