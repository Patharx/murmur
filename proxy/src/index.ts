// Murmur's only piece of server infrastructure.
//
// It verifies the caller is a real Google account, checks a per-user daily
// count, and forwards the request to Anthropic with the real API key attached.
// It logs nothing, stores no note content, and has no database. If it is
// breached the attacker gets an API key, not anyone's notebook.
//
// See docs/ARCHITECTURE.md §7 and docs/PRIVACY.md.

import { ProxyError, errorResponse, toResponse } from './errors';
import { bearerToken, verifyGoogleIdToken } from './google';
import { normaliseRequest } from './policy';
import { checkAndIncrement } from './ratelimit';

export interface Env {
  /** The real Anthropic key. `wrangler secret put ANTHROPIC_API_KEY`. */
  ANTHROPIC_API_KEY: string;
  /** Comma-separated Google OAuth client IDs the ID token may be issued to. */
  GOOGLE_CLIENT_IDS: string;
  /** KV namespace holding one integer per user per day. */
  RATE_LIMIT: KVNamespace;
  /** Requests per user per day. Defaults to 200 (docs/ARCHITECTURE.md §7). */
  DAILY_REQUEST_LIMIT?: string;
}

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
const MAX_BODY_BYTES = 1_048_576; // 1 MB — a two-hour transcript is well under this
const DEFAULT_DAILY_LIMIT = 200;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch (e) {
      return toResponse(e);
    }
  },
};

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === '/health' && request.method === 'GET') {
    return new Response('ok\n', { headers: { 'content-type': 'text/plain' } });
  }
  if (url.pathname !== '/v1/messages') {
    return errorResponse(404, 'not_found_error', 'There is nothing at that address.');
  }
  if (request.method !== 'POST') {
    return errorResponse(405, 'invalid_request_error', 'Send a POST.');
  }

  const sub = await verifyGoogleIdToken(bearerToken(request.headers.get('authorization')), audiences(env));

  const { body, stream } = normaliseRequest(await readJsonBody(request));

  const limit = dailyLimit(env);
  const rate = await checkAndIncrement(env.RATE_LIMIT, sub, limit);
  if (!rate.allowed) {
    return errorResponse(
      429,
      'rate_limit_error',
      `That's ${limit} read-backs today. There'll be more tomorrow.`,
    );
  }

  const upstream = await fetch(ANTHROPIC_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
  });

  const headers = new Headers();
  headers.set('content-type', upstream.headers.get('content-type') ?? 'application/json');
  const requestId = upstream.headers.get('request-id');
  if (requestId) headers.set('request-id', requestId);
  headers.set('x-murmur-requests-remaining', String(rate.remaining));
  if (stream) headers.set('cache-control', 'no-cache');

  // The body is streamed straight through. Nothing here reads it, buffers it,
  // or writes it anywhere.
  return new Response(upstream.body, { status: upstream.status, headers });
}

function audiences(env: Env): string[] {
  const ids = (env.GOOGLE_CLIENT_IDS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (ids.length === 0) {
    throw new ProxyError(500, 'api_error', 'This proxy is not configured yet.');
  }
  return ids;
}

function dailyLimit(env: Env): number {
  const parsed = Number.parseInt(env.DAILY_REQUEST_LIMIT ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_DAILY_LIMIT;
}

async function readJsonBody(request: Request): Promise<unknown> {
  const declared = Number.parseInt(request.headers.get('content-length') ?? '', 10);
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    throw new ProxyError(413, 'request_too_large', 'That note is too long to read back in one go.');
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new ProxyError(413, 'request_too_large', 'That note is too long to read back in one go.');
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new ProxyError(400, 'invalid_request_error', "The request body wasn't readable JSON.");
  }
}
