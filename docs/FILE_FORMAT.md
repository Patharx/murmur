# The Murmur file format

This is a public contract. Murmur writes these files into a folder in your own Google Drive; other
tools are welcome to read and write them. If Murmur disappears, your notebook does not.

## Layout

```
Murmur/
  Unlabeled/                      inbox for a voice note you have not refiled yet
  <Folder name>/
    YYYY-MM-DD-HHmm-<slug>.md     the note
    YYYY-MM-DD-HHmm-<slug>.m4a    the first audio, if there is any
    YYYY-MM-DD-HHmm-<slug>.m4a    a later clip, with its own time, never the first file's path
  Walks/
  Reflections/
  Written/
  Reading/
  Odds and ends/
  Recaps/
    weekly/YYYY-Www.md
  .murmur/
    index.json
    device-<uuid>.json
```

Folders in the app are folders on disk. A note's location *is* its folder — if you move the file,
you have refiled the note, and Murmur will agree with you on the next sync.

Voice notes start in `Unlabeled` until you refile them. Written notes have no `.m4a`. A note that
was typed and then dictated into has audio beside it, and `kind: hybrid`.

A note with one recording keeps a single `audio:` filename, usually sharing the note's basename.
A later recording is a new file. It is never written over an earlier one. The original `audio:`
line stays, so an older tool still sees the first clip, and `recordings:` lists every clip in order:

## The note

Markdown with YAML front matter.

```markdown
---
id: 01J9F3ZK7M2QW8XN4V6B0PCTGD
created: 2026-08-06T07:42:11+01:00
modified: 2026-08-06T07:58:02+01:00
kind: voice            # voice | written | hybrid
folder: Walks
audio: 2026-08-06-0742-fathers-garden.m4a   # the first clip; omitted when there is none
phone_only: true       # omit the key when the note may be copied to Drive
recordings: [2026-08-06-0742-fathers-garden.m4a, 2026-08-06-1542-fathers-garden.m4a]
                                   # only when there is more than one clip
duration: 258          # seconds; omitted for written notes
title: My father's garden, and the thing about rows
threads: [Your father, Writing, Inheritance]
summary_model: claude-haiku-4-5             # omitted when unsummarised
summary_at: 2026-08-06T07:59:40+01:00
---

## The gist

- Bullets, written by the model.

## What you said

The transcript, or the typed body.

— Added 3:42 PM

Words from a later clip. The line is the time that clip was kept.
```

### Rules

- **`id` is a ULID and is the only identity.** Filenames change when titles change. Drive file IDs
  change when a file is copied. The ULID survives both and is generated offline.
- **`## The gist` and `## What you said` are structural.** Parsers find sections by these exact
  headings. No gist section means the note is unsummarised — deleting the section by hand is a
  legitimate way to ask for it to be regenerated.
- **Everything the app knows is in the file.** There is no app-only metadata. This is what makes the
  folder a real export rather than a backup of something else.
- **Unknown front-matter keys are preserved verbatim.** Future versions will add keys; older clients
  and third-party tools must not destroy them.
- Filenames are display, not identity. `YYYY-MM-DD-HHmm-<slug>`. The slug is ASCII, lowercase,
  and the first two meaningful words of the title: apostrophes drop out, accents fold, and
  stopwords (`the`, `and`, `my`, `about`, …) are skipped. "My father's garden, and the thing
  about rows" is `fathers-garden`. A collision adds `-2`, `-3`, and so on.
- `recordings`, when present, is the full list of audio files in the order they were kept.
  `audio` remains the first of them. A file with only `audio` is still a complete note.
- **`phone_only: true` means a sync must not upload this note.** Omit the key otherwise.
  Turning it on after a copy is already in Drive does not delete that copy. The person deletes
  the Drive file themselves if they want it gone.

## Recaps

`Recaps/weekly/2026-W32.md` — same front matter shape, `kind: recap`, with `range_start` and
`range_end`. The body is prose, not bullets.

## Writing your own tools

Anything that can read a folder of Markdown can read a Murmur notebook. If you write something,
the two things to get right are: preserve unknown front-matter keys, and never change an `id`.
