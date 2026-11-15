# Murmur

A personal voice and note-taking app for iPhone. For the thought you had on a walk, the letter you
drafted at midnight, the three lines you copied out of a book.

Most voice-note apps are built for work — meetings, action items, follow-ups. This one isn't.

## How it works

- **Say it or write it.** Talking is the way in. Typing is there when you'd rather. Say it instead
  of typing, mid-sentence, and the words land in the same note.
- **Transcription happens on your iPhone.** The audio doesn't have to go anywhere.
- **Your notes live in your own Google Drive**, as `.m4a` and `.md` files in folders that mirror the
  app. Readable in any text editor. See [FILE_FORMAT.md](docs/FILE_FORMAT.md) — it's a public
  contract, and Murmur disappearing does not take your notebook with it.
- **On Sunday it reads your week back to you** in a hundred words of plain prose. Not bullets, not a
  dashboard.
- **Threads** are the things you keep returning to, noticed automatically. A thread with fourteen
  months in it shows you how something moved.
- **Ask it a question** about your own notebook and get one answer, with the notes it read.

## What it deliberately doesn't have

No streaks. No tags. No sharing or collaboration. No chat thread. No subscription. No email digest,
and no email address collected. Each of those is a decision, not an omission —
[docs/DESIGN_SPEC.md](docs/DESIGN_SPEC.md) §6 says why.

## Privacy

There is no Murmur server holding your notes. [PRIVACY.md](docs/PRIVACY.md) is short and specific.

## Price

One payment, no subscription. It includes about five years of read-backs; after that you can add
your own Anthropic API key for nothing, or buy another five years. The notebook itself — capture,
transcription, sync, search, folders, threads — never expires and needs no account.

## Building it

See [CLAUDE.md](CLAUDE.md) for the working agreement, then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

`design/Murmur.dc.html` opens in a browser and is the interactive design reference.

## Licence

MIT for the app. The design files under `design/` are provided so you can build it faithfully.
