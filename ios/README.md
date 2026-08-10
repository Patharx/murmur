# ios/

The SwiftUI app. Not built yet.

Build order is in [CLAUDE.md](../CLAUDE.md) and must not be reordered:

1. Local store + capture + transcription. No Drive, no Claude.
2. Quick capture — App Intent, Action Button, Lock Screen control, Siri.
3. Drive sync.
4. Note gists, with the short-note gate.
5. Threads.
6. Weekly recap.
7. Ask.

Steps 1–2 are a complete, useful app on their own. Ship them to yourself and live with
them for a month before starting step 3.

The layout this directory is expected to grow into:

```
ios/Murmur/
  Capture/        AVAudioRecorder, SpeechAnalyzer, quick-capture App Intents
  Store/          note parser/serialiser, SQLite index, file layout
  Sync/           Drive client, changes feed, conflict resolution
  Intelligence/   prompts, proxy client, scheduling, on-device retrieval
  Threads/        thread index, arc generation
  UI/             screens — build to docs/DESIGN_SPEC.md
```

The note format the `Store/` layer must read and write is a public contract:
[docs/FILE_FORMAT.md](../docs/FILE_FORMAT.md). Write the parser round-trip tests before
the UI — unknown YAML front-matter keys have to survive a read-modify-write untouched.

The client for the back end in [`proxy/`](../proxy) belongs in `Intelligence/`. Its
request and response shapes are documented in [proxy/README.md](../proxy/README.md).
