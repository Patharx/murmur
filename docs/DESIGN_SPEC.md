# Murmur — build spec

Fidelity: **high**. Every value below is final. The reference prototype is `Murmur.dc.html`, option
`1a` — open it in a browser and tap through it before building. Options `1b`–`1e` are explorations
and are **out of scope**.

Target: iPhone, 402 × 874pt (iPhone 16 Pro). Dark only — the design system has no light mode and the
product does not want one.

## 1. Tokens

From the Nocturne design system (`styles.css`). Define these once in Swift and never write a literal
hex anywhere else.

### Colour

| Token | Hex | Use |
| --- | --- | --- |
| bg | `#161826` | App ground |
| surface | `#232532` | Cards, rows, inputs |
| text | `#e9e9ed` | Primary text |
| accent | `#9184d9` | Record button fill, active dot, glow |
| accent-400 | `#b5abfc` | Accent text, icons, active tab |
| accent-300 | `#d2cefd` | Accent text at body size |
| accent-700 | `#5d5294` | Hover edges |
| accent-800 | `#423a6a` | Summary card gradient top |
| neutral-800 | `#3f424d` | Hairline card edge |
| section | `#262a60` | Recap card ground |
| section-glow | `#353b80` | Recap radial bloom |

Text opacities on `text`: primary 100%, secondary 60%, tertiary 45%, quaternary 40%.
Rule/divider: `rgba(233,233,237,0.08)`. Card edge: 1px `#3f424d`, drawn as a border — on this dark
ground elevation is an edge plus ambient darkness, never a stacked shadow.

**The accent is a line and a glow, never a flood.** The only filled accent surfaces in the whole app
are the record button and the toggle tracks. Primary actions are outlined: 1px `rgba(145,132,217,0.55)`
border, transparent fill, `#b5abfc` label.

### Type — Inter throughout, headings at weight 500, never bolder

| Role | Size | Weight | Tracking | Line height |
| --- | --- | --- | --- | --- |
| Screen title | 29 | 500 | −0.025em | 1.15 |
| Today headline | 28 | 500 | −0.025em | 1.2 |
| Onboarding headline | 31 | 500 | −0.025em | 1.18 |
| Note title (detail) | 25 | 500 | −0.022em | 1.25 |
| Recap headline | 20 | 500 | −0.015em | 1.4 |
| Row title | 15 | 500 | −0.01em | 1.3 |
| Body / transcript | 15 | 400 | 0 | 1.75 |
| Secondary | 13 | 400 | 0 | 1.55 |
| Caption | 12–12.5 | 400 | 0 | 1.45 |
| Meta | 11 | 400 | 0 | 1.4 |
| Section label | 11 | 600 | 0.12em, uppercase | 1.2 |
| Chip label | 10–10.5 | 600 | 0.08–0.14em, uppercase | 1.2 |
| Timer | 50 | 500 | −0.035em, tabular | 1 |

Use tabular figures for the timer, durations and any count.

### Spacing, radii

Screen padding 20pt horizontal. Card padding 14–17pt. Stack gaps: 20 between sections, 10–12 between
cards in a list, 4–9 within a card.

Radii: card 12, small control 8–10, chip/pill 5–8, large card 14, circle for record/avatar.

### Motion

- Screen enter: fade + 8pt rise, 280ms, ease-out.
- Record button pulse: scale 1 → 1.7, opacity 0.5 → 0, 2s, ease-out, infinite.
- Orb breathe (option 1c only): scale 1 → 1.07, 3.4s, ease-in-out.
- Toggle: 180ms ease.
- Summary spinner: 800ms linear rotation.

Nothing bounces. Nothing springs. The app is quiet.

## 2. Navigation

Five-slot tab bar, 86pt tall, background `rgba(22,24,38,0.88)` with an 18pt blur, 1px top rule at
`rgba(233,233,237,0.08)`.

`Today · Ask · [Record] · Weekly · You`

Note the change from the earlier prototype: **Find and Ask are one tab.** Typing a word searches;
typing a question gets an answer. They are the same intent — getting back to something you said —
and splitting them would have cost a tab slot for no gain. Threads live at the bottom of the same
screen as the browse fallback for when you have no query.

The record slot is a 56pt circle filled `#9184d9`, offset −22pt so it breaks the bar's top edge, with
a `0 6 22 rgba(145,132,217,0.4)` glow. Tab icons 21pt, inactive `rgba(233,233,237,0.42)`, active
`#b5abfc`, label 10pt/500.

Icons: Phosphor, regular weight, 1.9pt stroke.

## 3. Screens

### 3.1 Onboarding

Full-bleed, centred vertically. A 62pt breathing circle,
`radial-gradient(circle at 35% 30%, #b5abfc, #5d5294)`.

Headline: "Say it or write it. / I'll keep it either way."
Body: "The thought you had on a walk. The letter you drafted at midnight. The three lines you copied
out of a book. Murmur holds all of it in one notebook, and once a week reads it back to you."

Three numbered points (01/02/03 in `#9184d9`):
01 — Spoken or typed, it all lands in the same place. Transcription happens on your iPhone.
02 — Everything is kept on the device first, then copied to your own Drive as files you can still
     read without this app.
03 — It's open source. Nothing here is a subscription to your own thoughts.

Outlined button, full width, 14pt padding, radius 10: **Start my notebook**

Only claim these if §10 of ARCHITECTURE.md stays true.

### 3.2 Today — the default screen

1. **Date label** (section label style) + **headline** (28pt). The headline is *generated and
   truthful*, derived from the actual note set: on "All", the count of today's notes and, if two or
   more share a thread, that fact. On a selected folder, that folder's count. Never a fixed string —
   the prototype had a bug here precisely because it was hardcoded.
2. **Two icon buttons**, 37pt, radius 10, 1px `rgba(233,233,237,0.14)`: pencil (compose) and search.
3. **Weekly recap card** — radius 14, `linear-gradient(150deg, #262a60, #1d2043)`, 1px
   `rgba(145,132,217,0.32)`, with a 150pt radial bloom of `#4c5397` at 45% opacity bleeding off the
   top-right corner. Star icon + "SUNDAY · YOUR WEEK" in `#b5abfc`; a 16.5pt headline;
   "Read it back · a minute". Taps to Weekly.
   **This card appears only while the week's recap is unread.** Once read, it goes, and Today is
   just the date, the headline and the notes. There is no daily recap and no empty state — an
   ordinary Tuesday shows no card at all, and that is correct. Do not fill the space.
4. **Folder chips** — horizontal scroll. Inactive: transparent, 1px `rgba(233,233,237,0.14)`,
   `rgba(233,233,237,0.6)`. Active: `rgba(145,132,217,0.16)` fill, `#9184d9` border, `#b5abfc` text.
   Order: All, Unlabeled, Written, Walks, Reflections, Reading, Odds & ends.
   Unlabeled is the inbox a new voice note lands in. Odds & ends stays its own folder.
5. **Note list** — surface cards, radius 12, 1px `#3f424d`, hover/press edge `#5d5294`.
   30pt rounded-square icon tile, `rgba(145,132,217,0.14)`: microphone for voice, three lines for
   written. Title 15/500; preview 12.5pt at 50% opacity, clamped to 2 lines; meta row of
   time · duration · folder separated by 2pt dots at 30% opacity.
   **If the note is not yet uploaded**, append an "ON PHONE" chip: 10pt/600 uppercase, 1px
   `rgba(233,233,237,0.14)`, with a small up-arrow glyph.

### 3.3 Recording

Cancel ("Never mind") / "LISTENING" with a 7pt `#9184d9` dot and a 10pt glow / spacer.

Timer 50pt tabular, centred. Beneath it: "Written down on this iPhone — nothing sent yet".

**Waveform**: 40 bars, 3pt wide, 2pt radius, `#9184d9` at 85%, height 6–68pt, driven by the live
audio level, 100ms linear height transitions. Must respond to actual input level — a fake animation
is detectable and undermines the one thing this screen exists to communicate.

**Live transcript** card: surface, radius 12, label "AS YOU SPEAK", 15pt/1.7 body at 85% opacity,
with a `#9184d9` caret. Per ARCHITECTURE §9 this is a confidence display; the authoritative
transcript is produced afterwards from the file.

**Controls**: pause (52pt outlined circle) / stop (74pt `#9184d9` circle with a 23pt rounded square
in `#161826`, pulsing ring, 32pt glow) / bookmark (52pt outlined circle).

Bookmark drops a timestamp into the note — the transcript gets a marker the user can jump to.

### 3.4 Compose (written notes)

Header: "Close" / "WRITTEN" / "Keep" (`#b5abfc`, 500).

Title 23pt/500. Body 15.5pt/1.75 — **`white-space: pre-wrap` equivalent; paragraph breaks must
survive.** In SwiftUI this is free with `Text`, but verify with a multi-paragraph note.

Footer, above the keyboard:
- A check glyph + "Kept on this iPhone as you type — no connection needed". This must be literally
  true (ARCHITECTURE §4).
- Folder chips (Written / Reflections / Reading / Odds & ends).
- **Drive toggle row** — surface card, cloud icon, title toggling between "Copy to Google Drive" and
  "Keep on this phone only", subtitle explaining the .md file, and a 44 × 26pt switch with a 20pt
  knob. Track `#9184d9` on, `#3f424d` off.
- Format bar: Aa · List · Quote · **Dictate into this note** — the last one appends a voice segment
  to a written note, which is the feature that makes the two capture modes one product rather than
  two apps sharing a tab bar.

### 3.5 Note detail

Back ("Today") + export and overflow icon buttons (34pt, radius 9).

Title 25pt/500. Meta row: time · duration · folder, then a **sync chip** — "ON DRIVE" in tertiary
grey, or "ON PHONE · PUSH UP" in `#b5abfc` with an accent border, which is **tappable** and uploads
that note immediately.

**Audio player** — only for voice notes; omit the block entirely for written ones. Surface card:
38pt circular play button in `rgba(145,132,217,0.16)`, 32-bar waveform (played portion `#b5abfc`,
remainder `rgba(145,132,217,0.4)`), duration in tabular figures.

**Summary card** — radius 12, `linear-gradient(155deg, rgba(66,58,106,0.5), rgba(35,37,50,0.65))`,
1px `rgba(145,132,217,0.28)`. Header: star + "THE GIST" in `#b5abfc`, right-aligned "Claude · a
moment ago". Three states:
- *Unsummarised*: outlined button, "Read it back to me".
- *Loading*: 15pt spinner + "Reading it back…".
- *Done*: bullets with `#9184d9` em-dashes, 14pt/1.6; then thread chips, 11.5pt, 1px
  `rgba(233,233,237,0.14)`.

There is no fourth state. Guard against a summarised note with no summary content — that was a real
bug in the prototype.

**Transcript** — label "WHAT YOU SAID", 15pt/1.75 at 78%, paragraph breaks preserved.

### 3.6 Weekly

**Weekly only. There is no daily recap.**

Title "Read back", then the **letter card** — radius 14, `linear-gradient(160deg, #262a60, #1a1c33)`,
1px `rgba(145,132,217,0.28)`. "SUNDAY, FROM YOUR WEEK" at 10pt/600/0.16em in `#b5abfc`; the recap as
**prose** at 15pt/1.75 with paragraph breaks preserved; a fading accent rule; three inline stats
(18pt value, 9.5pt uppercase label).

Prose, not bullets — this is option `1d` from turn 1, adopted. A personal week is a shape, not a set
of items; prose can say *"you'd stopped arguing with it"* and a bullet list structurally cannot.
Hard cap 130 words.

Below: week chips (This week / previous dates) for browsing back, then the thread cards and
carry-forward card as before.

Footer: "Written on Sunday morning, and kept in your Drive alongside the notes it came from."

### 3.7 Ask

One field, two behaviours. A word searches; a question is answered.

**Idle state**: the field, a line of explanatory copy ("A word finds notes. A question gets an
answer — either way it's all your own words."), and three suggested questions as outlined rows with
a star glyph, 1px `rgba(145,132,217,0.3)`, text `#d2cefd`. The suggestions are generated from the
user's own threads and should change — they are how anyone discovers this feature exists.

**Thinking state**: the summary-card gradient with a spinner and "Reading back through 214 notes…".
Name the real number; it is what makes the feature feel like it is reading *your* notebook.

**Answered state**: same gradient card. Answer at 14.5pt/1.7, paragraph breaks preserved, capped
around 200 words. Then a fading accent rule, then **"READ FROM"** and up to four source notes as
tappable rows with 4pt accent dots.

The sources are not decoration. They are what keeps this a notebook rather than an oracle, and they
are the difference between the user trusting it and the user quietly checking it. Always render
them; if the model returns none, show the retrieved notes instead.

**No conversation.** One question, one answer. No follow-up field, no history, no thread. Tapping
the search field resets to idle.

Below the answer area: matching notes, then the **Threads** list (§3.9).

Retrieval is on-device — FTS5 plus `NLEmbedding` re-ranking (ARCHITECTURE §8a). Search results are
instant and offline; only asking a question requires network.

### 3.9 Threads

**List** (bottom of Ask): section label, the line "The things you keep coming back to, whether or
not you meant to.", then surface rows — name at 15/500, "14 notes · since March" at 12pt/45%,
chevron.

**Detail**: back to Threads / "THREAD" label / name at 29pt / "14 notes since March · last
Yesterday".

Then the **arc card** — the summary-card gradient, "HOW IT'S MOVED" in `#b5abfc`, one or two
sentences at 14.5pt. This is the screen's reason to exist: *"It started as the house. Around June it
stopped being about the house. Last week you made a plan."*

Then a vertical timeline: 1px accent line fading at both ends, 9pt dots ringed 3pt in the page
ground, date at 11pt/40%, title at 15/500. Dots fade with age — `#9184d9` recent, `#5d5294` mid,
`#423a6a` old.

Reached from: the Threads list, and the thread chips on any note's gist card (make those tappable).
No new tab. That is the whole navigation cost of the feature.

### 3.8 You (settings)

**Where your notes live** — radio list: Google Drive (with "Murmur/ — 214 notes, synced 4 min ago"),
Dropbox, OneDrive, "Just this iPhone". 19pt radio, filled `#9184d9` with a `#161826` check when on.
Explanatory footer about the .m4a/.md layout. Then a **"Push N notes up now"** action row in
`#b5abfc` — the count comes from `synced_mtime < local_mtime`.

Dropbox and OneDrive are shown in the design as intent. **Ship Drive only in v1** and either hide the
others or mark them "soon" — a dead radio button is worse than an absent one.

**Reading back** — four toggle rows: a letter on Sunday · notice recurring threads · the gist on
longer notes ("Skipped on anything under a minute — short notes are their own summary") · let me ask
my notes questions ("Searching happens on this phone; only the notes it finds are read").

Footer: "Transcription runs on your iPhone. Only the text goes to Claude, and only for the parts you
turn on above."

The short-note gate is surfaced as a *toggle subtitle* rather than hidden, because "we don't bother
you with a summary of a three-line note" is a statement of taste and worth saying out loud.

That sentence is a promise the code must keep. If a toggle is off, no call is made.

**Open source row** — GitHub mark, "Murmur is open source", "Read the code, or run it against your
own API key" — links to the repo and to the BYO-key field (ARCHITECTURE §7, Option B).

## 4. Copy rules

The vocabulary is the product. Enforce it in review:

- "Listening", never "Recording". "Read back", never "Summary" or "Insights". "The gist", never
  "Key points". "Worth keeping" / "Carrying into next week", never "Action items". "Never mind",
  never "Cancel" where a human would hesitate. "Keep", never "Save". "Say it instead", never
  "Dictate". "How it's moved", never "Timeline" or "Activity".
- Second person, past tense, warm and dry.
- No emoji. No exclamation marks. No celebration of streaks or volume.
- Never congratulate the user for using the app.

## 5. Accessibility

- Dynamic Type: support to at least XXL. The 15pt body and 11pt meta are the pressure points; the
  note list row must reflow rather than truncate.
- Every icon button needs a label — the pencil, search, bookmark and sync chip are all unlabelled
  visually.
- The waveform is decorative; mark it `.accessibilityHidden`. The timer must announce.
- Contrast: `#b5abfc` on `#161826` passes for large text and UI; body-size accent text uses
  `#d2cefd`. Do not put 13pt `#9184d9` text on the ground.
- Respect Reduce Motion: drop the pulse and the breathe, keep the fades.

### 3.10 Say it instead (dictation inside a written note)

In the compose screen's format bar, an outlined button: microphone glyph + "Say it instead".

Tapping it swaps the format bar for a **dictation bar** on the summary-card gradient: a 38pt pulsing
accent circle, a 26-bar live waveform driven by input level, "Carries on where you left off · 0:14",
and a "Done" button.

**The dictated words arrive tinted** — `rgba(181,171,252,0.95)` — appended at the cursor,
mid-sentence, and settle to normal body colour `rgba(233,233,237,0.8)` when Done is tapped.

That tint is the design. It marks the text you have not proofread yet, so recognition errors are not
silently absorbed into something you believe you wrote. Do not skip it.

The audio is **kept**, not discarded — the note becomes a hybrid with an .m4a beside its .md, and
`kind: hybrid` in the front matter. This is why the label is "Say it instead" rather than "Dictate":
dictation implies the voice was a means to text. Here it is just the other way of talking, and it is
the single feature that makes voice and typing one product rather than two tabs sharing an app.

On-device recognition, streaming into the buffer at the cursor. Works with no network.

## 4a. Quick capture — outside the app

Highest-priority item in the whole build, and it adds no screens.

- **App Intent** — `StartMurmurIntent`, begins recording immediately, no UI.
- **Action Button** — press and hold; recording before the phone is out of the pocket.
- **Lock Screen / Control Center control** — one tap, no Face ID, no unlock.
- **Siri** — "Hey Siri, murmur."

All four land in the same place: recording, transcribing on device, filed to *Odds & ends* until the
user says otherwise. A short haptic on start and on stop is the entire feedback; do not present UI.

The rationale: the stated primary uses are walking and driving, where the current path is phone out,
unlock, find app, load, tap record — about eight seconds, which the thoughts this product exists to
catch do not survive. Roughly a day of work each.

## 6. Out of scope for v1

- **Daily recap** — cut. See CLAUDE_LAYER §1. May return behind a one-time unlock.
- **Email digest** — cut permanently. ARCHITECTURE §8.
- **Tags, streaks, sharing** — rejected. Threads replace tags; streaks turn a notebook into a work
  app; sharing is the clearest signal a personal app is becoming one.
- **Dropbox / OneDrive** — designed but not shipped in v1. Hide the rows rather than showing dead
  radio buttons.
- Prototype options `1b` (day-thread home), `1c` (orb recording UI), `1e` (no tab bar, hold-to-talk,
  year heat-map) — documented in `Murmur.dc.html` with reasoning. `1c` and `1e` are the strongest
  v2 candidates. `1d` (prose recap) has been **adopted** into §3.6.
