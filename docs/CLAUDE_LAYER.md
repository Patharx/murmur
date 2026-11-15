# Murmur — the Claude layer

Everything here runs on **text**. Audio never reaches Anthropic; the transcript does, and only for
features the user has switched on.

## 1. Four jobs

| Job | Trigger | Input | Output | Model |
| --- | --- | --- | --- | --- |
| Note gist | User taps "Read it back to me", or auto-on-save | One transcript, **only if it is at least 80 words and, when there is audio, at least a minute** | 2–3 sentences + threads | Haiku |
| Weekly recap | Local schedule, Sunday 09:00 | The week's note gists | 100–130 words of prose | Haiku |
| Thread arc | When a thread gains a note (debounced, max once/day/thread) | That thread's gists | One or two sentences | Haiku |
| Ask | User asks a question | Question + top ~10 retrieved notes | Prose answer + sources | Haiku |

**There is no daily recap.** It was cut deliberately: it was ~75% of the running cost, and once a
week is the right cadence for a reflective notebook — a daily read-back of three notes has little to
notice and starts to feel like a nag. Keep the code path general enough that a daily could be added
later behind a one-time unlock, but do not build it now.

**The short-note gate is a product decision, not just a cost one.** A three-line note about a fence
does not need a summary, and a summary of it is *worse than nothing* — it pads, it restates, and it
makes the feature feel automatic rather than attentive. Skip the gist when the note is under 80
words **or** under one minute of audio. Either condition is enough. A written note has no duration,
so only the word count applies. Show no gist card at all. This also removes roughly a third of gist calls.

**The weekly reads gists, not transcripts.** Cost stays flat no matter how much the user recorded,
and the writing is better because the per-note pass already discarded the noise.

## 2. Prompt caching

Cache the system block (§3.1) with `cache_control: {"type": "ephemeral"}`. It is identical across
every gist call and every weekly, and gist calls cluster (a user finishes a walk, three notes get
processed together).

**On Haiku 4.5 this will not actually fire.** Its minimum cacheable prefix is 4096
tokens and the system block is nowhere near that, so the marker is ignored silently —
no error, `cache_creation_input_tokens` simply stays 0. Send it anyway: it costs
nothing and starts working by itself if the block ever grows. Do not budget the saving.

Order the prompt cached-prefix-first: system block, then the per-note content. Do not interpolate
anything variable into the system block — including the date, which is tempting and would break the
cache on every call.

## 3. Scheduling without a server

`BGTaskScheduler` with a `BGProcessingTaskRequest` (needs network; does not need power). iOS decides
when to run it, and "Sunday 09:00" is a request, not a guarantee.

Design for that rather than fighting it:

- If Sunday's task did not run, generate on next app foreground before showing Today.
- Never skip a week silently. A missed week is generated late and labelled with its date range.
- A recap already written is never regenerated. Check for `Recaps/weekly/<year>-W<week>.md` first.
- The UI never promises a time. The Today card says "Sunday · your week", not "at 9am".
- Gist calls do **not** wait for the background task — they run when a note finishes processing, or
  on demand from the note detail button.

## 3. Prompts

### 3.1 System prompt — shared

```
You are reading back a person's private notebook to them. You are not an assistant, a coach, or a
productivity tool. You do not give advice unless the note explicitly asks a question of itself.

Voice: plain, warm, second person, past tense. Write the way a close friend who was listening would
summarise it back — accurate, unsentimental, a little dry. Never therapeutic.

Never use: journey, unpack, dive into, actionable, takeaway, insight, growth, reflect on your,
it's clear that, it sounds like you're feeling. Never open with "It sounds like".

Never praise the person for having recorded a note. Never encourage them to keep it up.
If a note is mundane, say what it is. Not everything is meaningful and pretending otherwise is
the fastest way to make this feel fake.

Use the person's own words for their own things — if they said "the fence", say "the fence", not
"your home maintenance task".
```

That block of banned phrases is doing real work. It is the difference between the product's stated
positioning and yet another wellness app.

### 3.2 Note summary

```
Here is a note, recorded <date> at <time><, while walking / typed>.

<transcript>

Write:
1. Two or three bullets, each one sentence, saying what the person worked out or decided.
   Not what topics they covered — what they concluded. If they concluded nothing, say what they
   were turning over.
2. A line "THREADS: a, b, c" — two to four short noun phrases naming what this note is about, using
   their own vocabulary. These group notes across weeks, so prefer stable names ("Kate", "the
   fence", "Reading") over one-off descriptions.

No preamble, no heading, no closing line.
```

Model: **Haiku**. This runs on every note and the task is genuinely easy — and it is the
model every other job here uses too. If evaluation ever shows it
failing on long, rambling notes, that is a change to proxy/src/policy.ts as well as
to this table.

Max tokens 300. If the transcript exceeds ~15,000 words (about two hours of speech), summarise in
two passes rather than truncating — truncation silently drops the end of a note, which is usually
where the person got to the point.

### 3.3 Daily recap — CUT, retained for reference only

```
Here are the notes this person made on <weekday date>.

<for each: time, title, kind, summary bullets, threads>

Write:
1. HEADLINE: one sentence, max 90 characters, saying what the day was actually about. If several
   notes circle the same thing, say so — that is usually the true headline. If the day was
   scattered, say that instead of inventing a theme.
2. THREADS: for each thread appearing in two or more notes, its name and one sentence on how it
   moved during the day. Movement matters more than content: "you went from rehearsing the
   argument to deciding you do not want to have it" is the shape worth naming.
3. CARRYING: up to three things they said they would do, or said they keep meaning to do, in their
   own words. If they have said the same one before, say which week they first said it.
   Omit this section entirely rather than padding it.
```

Not built for v1. If it returns behind a one-time unlock, note that the "you have said this before"
behaviour needs the previous 14 days' CARRYING lines passed in — a few hundred tokens, and the most
distinctive thing the feature does.

**That behaviour has moved to the thread arc (§3.5) instead**, where it works better: a thread
already knows every time you have mentioned something, so *"you have now meant to call Dev three
times"* falls out of the data rather than needing a rolling history window.

### 3.4 Weekly recap

```
Here are the gists of every note this person made between <date range>.

<for each: day, time, title, gist bullets, threads>
<counts: notes, minutes spoken, notes written>

Write 100–130 words of continuous prose, addressed to them, about their week. Not a list.
Find the one thread that actually moved and give it most of the words. Name the specific note where
it turned, by day. Mention what else was going on in a clause, not a paragraph.
End on a fact, not a feeling. Do not offer advice or encouragement.
```

Model: **Haiku**. Hard cap 130 words — a long weekly recap does not get read, and length is where
the tone goes wrong.

### 3.5 Thread arc

```
Here is every note this person has filed under the thread "<name>", oldest first.

<for each: date, title, gist bullets>

Write one or two sentences saying how this has moved over time — what it started as and what it
became. If it has not moved, say that plainly. If they have repeatedly said they would do
something and not done it, say how many times and when they first said it.

No preamble. Present tense for where it stands now.
```

Model: **Haiku**. Regenerate only when the thread gains a note, debounced to once per day per
thread, and cache the result in the thread's front matter. A user with 40 threads must not trigger
40 calls on launch.

### 3.6 Ask

The one place a user types a question. Retrieval happens **on the device**; only the notes it finds
are sent.

1. Run the question through SQLite FTS5 over titles, gists and bodies.
2. Re-rank with on-device embeddings (`NLEmbedding`, or `NLContextualEmbedding` for better recall).
   No network, no vector service, no cost.
3. Take the **top 10 notes, capped at ~8,000 tokens** of gists — send gists, not full transcripts,
   unless fewer than four notes matched.
4. Send question + those notes.

```
This person asked a question about their own notebook. Below are the notes most likely to be
relevant, oldest first. Answer only from these notes.

<question>
<notes: date, title, gist>

Answer in two or three short paragraphs, second person, in the voice described above. Quote their
own phrasing where it is better than yours. Give dates — "around the 21st of June" is more useful
than "a while ago".

If the notes do not answer the question, say so plainly and say what they do cover instead.
Never infer beyond what is written. Never speculate about how they felt.
Do not give advice. Do not ask a follow-up question.

End with SOURCES: the titles of the notes you actually drew on, at most four.
```

Model: **Haiku**. The sources line is not decoration — it is the thing that keeps this feature
honest and keeps it feeling like a notebook rather than an oracle. Render each source as a tappable
row that opens the note.

Cap answers at ~200 words. Never open a chat thread: one question, one answer, no follow-ups. The
moment it has conversation history it stops being a notebook and becomes a chatbot, which is the
failure mode this product is defined against.

## 4. Cost

Per user, assuming an engaged one: 12 notes/week, ~700 words each. After the short-note gate strips
out anything under 80 words or under a minute of audio (§1). Prompt caching is not a factor here — it does not fire on Haiku
(§2), so it buys nothing to net out.

Worked from Haiku 4.5's real per-token price (\$1/\$5 per MTok, input/output) and each prompt's own
word counts above, at roughly 1.3 tokens per word. This traces back to this document rather than
being carried over from an earlier draft — if a prompt above changes, recompute the row it feeds.

| Call | Frequency | Model | ~Cost each | Monthly |
| --- | --- | --- | --- | --- |
| Note gist | ~36/mo (gate removes ~30%) | Haiku | \$0.0017 | \$0.061 |
| Weekly recap | 4/mo | Haiku | \$0.0022 | \$0.009 |
| Thread arcs | ~15/mo | Haiku | \$0.0013 | \$0.020 |
| Ask | ~6/mo | Haiku | \$0.0097 | \$0.058 |

**~\$0.15/user/month for an engaged user; ~\$0.06 for a typical one.** Cutting the daily recap took
roughly 75% of the previous running cost out. Note gists are the largest monthly line (\$0.061) —
not because they're expensive, but because there are 36 of them a month against Ask's 6. Per call,
Ask costs nearly six times as much as a gist (\$0.0097 vs \$0.0017, driven by the ~8,000-token
retrieval cap in §3.6), and it's the one line a single user can actually move: most people ask a
handful of questions a month, not a handful a day, but nothing stops someone from doing the latter.

Do **not** meter Ask visibly. Good retrieval is the cost control: sending 10 gists instead of a whole
notebook is the difference between a cent or two and several dollars a question. If someone
genuinely asks 200 questions a month they are the best user you have; eat it.

### 4.1 What this means for pricing

At ~\$0.15/mo, \$25 net of Apple's 15% (\$21.25) covers roughly **twelve years**. Claim five. Model
costs have fallen consistently and almost certainly will again, so understating is the safe
direction — a user who gets eight years out of a "five year" claim is delighted, and the reverse is
a support burden and a bad review.

Recommended: **\$25 one-time, "includes about five years of read-backs."** After that, add your own
API key for free or buy another five years. The notebook itself — capture, transcription, Drive
sync, search, folders, threads — is free forever with no account. What is being sold is the
read-back, and saying so plainly is a differentiator in a category built on obscuring it.

### 4.2 Your own account

You do not need anything special. Ship the bring-your-own-key field (ARCHITECTURE §7 Option B) and
put your own key in it — your usage then bills to your Anthropic account directly and never touches
the proxy. As the developer your own App Store purchases are free anyway, but the BYO field is the
cleaner path and it is a feature you were shipping regardless.

## 5. Failure states

Every call can fail, and this is a journal — never lose or fabricate.

- **Offline**: queue and retry. The note is complete and readable without a summary; the summary is
  an addition, never a prerequisite. Show the "Read it back to me" button in its unsummarised state.
- **API error**: retry twice with backoff, then surface a quiet inline "Couldn't read this one back
  — tap to try again". Do not use a modal. Do not use the word "error".
- **Refusal or empty response**: leave the note unsummarised. Do not display a placeholder summary.
  An empty state is honest; an invented one is not.
- **Recap with no notes**: do not generate, do not notify. A day with nothing in it is fine and does
  not need commentary.
- **A single note failing inside a daily recap**: proceed without it rather than failing the batch.

## 6. Evaluation

Write ~30 realistic transcripts before launch — rambling, mundane, emotional, half-abandoned — and
check the outputs against exactly two questions:

1. Would the person recognise this as what they said?
2. Does it sound like a friend or like software?

The banned-phrase list in §3.1 handles most of question 2 mechanically. Add to it every time
something syrupy gets through; that list is the tone spec and should keep growing.
