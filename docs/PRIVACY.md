# Privacy

Murmur is built so that we do not hold your notes. Not encrypted-so-we-can't-read-them — simply not
held. There is no Murmur server with a database on it.

## Where your notes are

On your iPhone, and in a folder in your own Google Drive if you turn that on. That is all. You can
open the folder, read the files, copy them, or delete them without us being involved.

## What leaves your phone

**Audio never leaves**, except to your own Drive as a backup, if you enable it.

**Transcription happens on your iPhone.** Apple's on-device speech recognition. No audio is sent
anywhere to be transcribed.

**Note text goes to Anthropic only for the read-back features you switch on**, and only the text —
never the audio. If a toggle is off, no call is made. Specifically:

- The gist: the note's transcript, for notes over ~80 words.
- The Sunday letter: that week's gists.
- Threads: the gists of the notes in that thread.
- Ask: your question, plus the handful of notes your question actually matched.

**Searching and asking happen on your phone.** Finding which notes are relevant to a question uses
on-device search and on-device embeddings. Only the matches are sent — never your whole notebook.

## What we never collect

- Your email address. There is no mailing list and no digest.
- Analytics on your notes: no counts, no topics, no sentiment, nothing.
- Your notes, in any form, on any server we operate.

## The proxy

Requests to Anthropic pass through a small proxy so that an API key does not have to ship inside the
app. It verifies you are a real user, forwards the request, and returns the response. It writes no
logs of note content and has no database. Its full source is in `proxy/` in this repository — it is
about 300 lines and you can read all of it.

If you would rather not route through us at all, put your own Anthropic API key in Settings and the
app will call the API directly. That path involves us not at all.

## Deleting everything

Delete the app, and delete the `Murmur` folder in your Drive. There is nowhere else.
