# The Murmur file format

This is a public contract. Murmur writes these files into a folder in your own Google Drive; other
tools are welcome to read and write them. If Murmur disappears, your notebook does not.

## Layout

```
Murmur/
  <Folder name>/
    YYYY-MM-DD-HHmm-<slug>.md     the note
    YYYY-MM-DD-HHmm-<slug>.m4a    the audio, if there is any
  Recaps/
    weekly/YYYY-Www.md
  .murmur/
    index.json
    device-<uuid>.json
```

Folders in the app are folders on disk. A note's location *is* its folder — if you move the file,
you have refiled the note, and Murmur will agree with you on the next sync.

Voice notes are an `.m4a` and a `.md` sharing a basename. Written notes have no `.m4a`. A note that
was typed and then dictated into has both, and `kind: hybrid`.

## The note

Markdown with YAML front matter.

```markdown
---
id: 01J9F3ZK7M2QW8XN4V6B0PCTGD
created: 2026-08-06T07:42:11+01:00
modified: 2026-08-06T07:58:02+01:00
kind: voice            # voice | written | hybrid
folder: Walks
audio: 2026-08-06-0742-fathers-garden.m4a   # omitted when there is none
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
- Filenames are display, not identity. `YYYY-MM-DD-HHmm-<slug>`, slug ASCII-only, max 40 chars.

## Recaps

`Recaps/weekly/2026-W32.md` — same front matter shape, `kind: recap`, with `range_start` and
`range_end`. The body is prose, not bullets.

## Writing your own tools

Anything that can read a folder of Markdown can read a Murmur notebook. If you write something,
the two things to get right are: preserve unknown front-matter keys, and never change an `id`.
