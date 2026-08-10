// What the proxy will and will not forward.
//
// The proxy is not a general Claude gateway. It exists so that one specific app
// can make four specific kinds of call (docs/CLAUDE_LAYER.md §1) without
// shipping an API key. Everything here is cost control, not security theatre —
// the rate limit in ratelimit.ts is the real bound.

import { ProxyError } from './errors';

/**
 * The only model the app is allowed to ask for.
 *
 * All four read-back jobs — note gist, weekly recap, thread arc and Ask — run
 * on Haiku 4.5 (docs/CLAUDE_LAYER.md §1). Anything else is a 403, so a bug in
 * the app cannot quietly start billing at a larger model's rates.
 */
export const ALLOWED_MODELS = new Set(['claude-haiku-4-5']);

/**
 * Ceiling on `max_tokens`.
 *
 * The largest documented value is 300 (a note gist). This is deliberately far
 * above that: it should never bind in normal use, and exists only so a bug in
 * the app can't run up a bill.
 */
export const MAX_TOKENS_CAP = 4096;

export type NormalisedRequest = {
  body: Record<string, unknown>;
  model: string;
  stream: boolean;
};

export function normaliseRequest(raw: unknown): NormalisedRequest {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new ProxyError(400, 'invalid_request_error', 'The request body should be a JSON object.');
  }
  const body = { ...(raw as Record<string, unknown>) };

  const model = body.model;
  if (typeof model !== 'string') {
    throw new ProxyError(400, 'invalid_request_error', 'The request is missing a model.');
  }
  if (!ALLOWED_MODELS.has(model)) {
    throw new ProxyError(
      403,
      'permission_error',
      `This proxy only forwards ${[...ALLOWED_MODELS].join(' and ')}.`,
    );
  }

  const maxTokens = body.max_tokens;
  if (typeof maxTokens !== 'number' || !Number.isInteger(maxTokens) || maxTokens < 1) {
    throw new ProxyError(400, 'invalid_request_error', 'The request needs a whole-number max_tokens.');
  }
  body.max_tokens = Math.min(maxTokens, MAX_TOKENS_CAP);

  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    throw new ProxyError(400, 'invalid_request_error', 'The request needs at least one message.');
  }

  if (body.stream !== undefined && typeof body.stream !== 'boolean') {
    throw new ProxyError(400, 'invalid_request_error', 'stream should be true or false.');
  }

  // Anthropic's `metadata.user_id` would put a user identifier on every
  // request. docs/PRIVACY.md promises only the note text leaves the phone, so
  // the field is dropped rather than forwarded.
  delete body.metadata;

  return { body, model, stream: body.stream === true };
}
