# Handoff: Murmur — iOS notebook (voice + written), Drive-backed

## Overview

Murmur is a personal note-taking and voice-recording app for iPhone. It is explicitly **not** a work
tool: no meetings, no action items, no productivity metrics. Users capture thoughts by speaking
(on a walk, driving) or by typing, everything lands in one chronological notebook organised by
folders, and on Sundays Claude reads the week back to them in plain language.

Three things define the architecture, and they are all consequences of one decision:

**Google Drive is the database.** There is no application server, no user database, no sync backend.
The phone writes files into the user's own Drive folder. That folder *is* the source of truth for
anything beyond the device. This removes the largest liability in the product — a central store of
other people's private journals — and removes almost all recurring cost.

Read `ARCHITECTURE.md` before writing any code. It is the load-bearing document.

## About the design files

The files in this bundle are **design references created in HTML** — a prototype demonstrating
intended look, copy, and behaviour. They are not production code and should not be ported or
transliterated. The task is to **rebuild these screens natively in SwiftUI**, using the measurements,
colours, type and copy documented in `DESIGN_SPEC.md`.

`Murmur.dc.html` is interactive: open it in a browser and tap through it. Option `1a` is the
prototype proper; `1b`–`1e` are alternate directions that were explored and are **not** in scope
unless the product owner says otherwise. Build `1a`.

## Fidelity

**High-fidelity.** Colours, type, spacing, radii and copy in the prototype are final and come from a
design system (Nocturne, included as `styles.css`). Reproduce them exactly — `DESIGN_SPEC.md` lists
every token. Where the HTML prototype and this documentation disagree, the documentation wins.

## What is actually being built

| Layer | Where it runs | Status |
| --- | --- | --- |
| Capture, transcription, editing | On device (SwiftUI + Speech) | Build |
| Local store — the real database | On device (SQLite index + files) | Build |
| Sync engine | On device (Drive REST v3) | Build — hardest part |
| Weekly recap generation | On device, scheduled Sunday | Build |
| Ask — retrieval | On device (FTS5 + NLEmbedding) | Build |
| Claude API access | Thin stateless proxy | Build — ~300 lines, stores nothing |
| Daily recap | — | **Cut.** ~75% of running cost, wrong cadence |
| Email digest | — | **Cut permanently.** No address is ever collected |
| Tags, streaks, sharing | — | **Rejected.** See DESIGN_SPEC §6 |

## Files in this bundle

- `README.md` — this file
- `ARCHITECTURE.md` — Drive-as-database, file layout, sync engine, the API-key problem
- `CLAUDE_LAYER.md` — prompts, batching, scheduling, cost model
- `DESIGN_SPEC.md` — screen-by-screen build spec, every token and measurement
- `Murmur.dc.html` — the interactive design reference (open in a browser)
- `ios-frame.jsx` — device bezel used by the prototype; not part of the product
- `styles.css` — the Nocturne design system tokens the design is built on

## Build order

1. **Local store + capture + transcription.** No Drive, no Claude. Ship this to yourself and use it
   for a week — it is a complete, useful app on its own, and it will tell you more about the product
   than any amount of planning.
2. **Quick capture** (DESIGN_SPEC §4a) — App Intent, Action Button, Lock Screen control, Siri.
   Roughly a day each and it is what makes step 1 a habit rather than a demo. Do this before the
   cloud work; you want a month of real notes accumulating while you build sync.
3. **Drive sync** (ARCHITECTURE §4–6). Expect this to take as long as step 1.
4. **Note gists** on demand — the "Read it back to me" button, with the short-note gate.
5. **Threads** — the index falls out of the gists, then the thread screen and arc.
6. **Weekly recap**, scheduled.
7. **Ask** last. It is the feature that most needs a real, large notebook to be worth anything, and
   you will not be able to judge its answers until you have one.

Do not build 4 before 3. Read-back quality depends on having real accumulated notes to run against,
and you will not have those until sync is trustworthy enough that you stop being afraid to use it.

## Pricing, for context

**\$25 one-time. "Includes about five years of read-backs."** The notebook — capture, transcription,
Drive sync, search, folders, threads — is free forever with no account. What is sold is the
read-back. After the included period: add your own API key for free, or buy another five years.

No subscription. Running cost is ~\$0.13/user/month for an engaged user (CLAUDE_LAYER §4), so the
numbers work and understating the duration is deliberate — model costs fall, and a user who gets
eight years from a five-year claim is delighted. Build the entitlement as a one-time StoreKit
purchase with a stored expiry date, and surface the remaining time honestly in Settings.
