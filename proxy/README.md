# proxy/

The only server Murmur has. It exists for one reason: **an API key cannot ship
inside a mobile app** ([docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) §7).

It verifies the caller is a real Google account, checks a per-user daily count,
and forwards the request to Anthropic with the real key attached. If it is
breached, the attacker gets an API key — not anyone's notebook.

## What it stores

One integer per user per day, in Workers KV, under the key
`rl:<google sub>:<UTC date>`. It expires by itself after 25 hours.

That is the complete list. No note content, no transcripts, no email addresses,
no request log, no database. The request body passes through memory on its way
to Anthropic and is gone. [docs/PRIVACY.md](../docs/PRIVACY.md) is a promise
this code has to keep — if you change anything here, re-read it.

## The contract

```
POST /v1/messages
Authorization: Bearer <Google ID token>
Content-Type: application/json

<an Anthropic Messages API request body>
```

The response is Anthropic's, streamed straight through — including SSE when the
body sets `"stream": true`. Errors come back in Anthropic's error shape, so the
app needs one parser rather than two:

```json
{ "type": "error", "error": { "type": "rate_limit_error", "message": "..." } }
```

| Status | `error.type` | Means |
| --- | --- | --- |
| 401 | `authentication_error` | Sign-in missing, malformed, expired, or not for this app. Refresh the Google token and retry once. |
| 403 | `permission_error` | A model this proxy doesn't forward. |
| 400 | `invalid_request_error` | Malformed body — a bug in the app, not something to retry. |
| 413 | `request_too_large` | Body over 1 MB. Summarise in two passes instead. |
| 429 | `rate_limit_error` | The day's allowance is spent. Queue and try tomorrow. |
| 503 / 500 | `api_error` | Transient. Retry with backoff, then leave the note unsummarised. |

Every successful response carries `x-murmur-requests-remaining`, and Anthropic's
`request-id` is passed through for debugging.

### What it will forward

- **Models**: `claude-haiku-4-5` only. All four read-back jobs run on it
  ([docs/CLAUDE_LAYER.md](../docs/CLAUDE_LAYER.md) §1). Anything else is a 403,
  including a dated variant like `claude-haiku-4-5-20251001` — the alias is what
  the app sends.
- **`max_tokens`**: clamped to 4096. The largest documented value is 300, so
  this should never bind; it is there so a bug in the app can't run up a bill.
- **`metadata`**: dropped. Anthropic's `metadata.user_id` would attach a user
  identifier to every request, and PRIVACY.md says only the text leaves the phone.
- **Body size**: 1 MB.

### Two things worth knowing on the client side

**Thinking is off unless you ask for it.** Haiku 4.5 does not think when the
`thinking` field is omitted, which is what the cost table in CLAUDE_LAYER.md §4
assumes. Leave the field out. (This is a real difference between model tiers —
Sonnet 5 and the Opus models *do* think by default, so if the model ever changes,
revisit this before the bill does.)

**Prompt caching will not fire, and that is fine.** CLAUDE_LAYER.md §2 asks for
`cache_control: {"type": "ephemeral"}` on the shared system block. Haiku 4.5's
minimum cacheable prefix is 4096 tokens and the system block in §3.1 is nowhere
near that, so the marker is silently ignored — no error, just
`cache_creation_input_tokens: 0`. Setting it anyway costs nothing and starts
working by itself if the block ever grows, so the app may as well send it; just
don't budget for the saving. The proxy forwards the body as-is either way.

## Deploying it

```bash
npm install
```

```bash
npx wrangler kv namespace create RATE_LIMIT
```

Paste the returned id into `wrangler.toml`, set `GOOGLE_CLIENT_IDS` there to the
iOS app's OAuth client ID, then:

```bash
npx wrangler secret put ANTHROPIC_API_KEY
```

```bash
npx wrangler deploy
```

For local work, copy `.dev.vars.example` to `.dev.vars` (gitignored) and run
`npx wrangler dev`.

## Tests

```bash
npm test
```

The ID-token tests are the ones that matter — they generate a real RSA key, sign
real JWTs, and check that a token for another audience, from another issuer,
with a swapped payload, with `alg: none`, or signed by a key Google doesn't
publish is refused. Auth is the whole security boundary here; if you change
`src/google.ts`, those tests are the thing that tells you whether you broke it.

```bash
npm run typecheck
```

## Not using it at all

Settings has a bring-your-own-key field
([docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) §7, Option B). A user who fills
it in calls `api.anthropic.com` directly from the phone and this proxy is not
involved. That path is what makes "run it yourself" true, and it is why this
directory can stay this small.
