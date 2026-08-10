// Google ID token verification.
//
// The app signs in with Google and sends the resulting ID token as a bearer
// token. We verify the signature against Google's published JWKS and check the
// standard claims. The only thing we take from a verified token is `sub` —
// Google's stable per-user identifier — which is used as a rate-limit key and
// is never stored.

import { ProxyError } from './errors';

const CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
const CLOCK_SKEW_SECONDS = 60;
const MIN_REFETCH_MS = 60_000;

type Jwks = { keys: Array<JsonWebKey & { kid?: string; alg?: string }> };

let cache: { keys: Map<string, CryptoKey>; expiresAt: number; fetchedAt: number } | null = null;

/** Verify a Google ID token and return its `sub`. Throws ProxyError on any failure. */
export async function verifyGoogleIdToken(token: string, audiences: string[]): Promise<string> {
  const parts = token.split('.');
  if (parts.length !== 3) throw badToken();
  const [rawHeader, rawPayload, rawSignature] = parts;

  const header = decodeSegment(rawHeader);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw badToken();

  const key = await keyForKid(header.kid);
  if (!key) throw badToken();

  const signed = new TextEncoder().encode(`${rawHeader}.${rawPayload}`);
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlToBytes(rawSignature) as BufferSource,
    signed as BufferSource,
  );
  if (!ok) throw badToken();

  const claims = decodeSegment(rawPayload);
  const now = Math.floor(Date.now() / 1000);

  if (typeof claims.iss !== 'string' || !ISSUERS.has(claims.iss)) throw badToken();
  if (typeof claims.aud !== 'string' || !audiences.includes(claims.aud)) throw badToken();
  if (typeof claims.exp !== 'number' || claims.exp + CLOCK_SKEW_SECONDS <= now) {
    throw new ProxyError(401, 'authentication_error', 'That sign-in has expired. Sign in again.');
  }
  if (typeof claims.iat === 'number' && claims.iat - CLOCK_SKEW_SECONDS > now) throw badToken();
  if (typeof claims.sub !== 'string' || claims.sub.length === 0) throw badToken();

  return claims.sub;
}

/** Read the bearer token from an Authorization header. */
export function bearerToken(header: string | null): string {
  const match = header?.match(/^Bearer (\S+)$/);
  if (!match) {
    throw new ProxyError(401, 'authentication_error', 'Missing sign-in token.');
  }
  return match[1];
}

function badToken(): ProxyError {
  return new ProxyError(401, 'authentication_error', "That sign-in didn't check out.");
}

async function keyForKid(kid: string): Promise<CryptoKey | undefined> {
  const now = Date.now();
  const stale = !cache || cache.expiresAt <= now;
  const unknownKid = cache !== null && !cache.keys.has(kid);
  // Refetch when the cache has expired, or when we see a kid we don't know —
  // but never more than once a minute, so an unknown kid can't be used to
  // hammer Google's certs endpoint.
  if (stale || (unknownKid && now - cache!.fetchedAt > MIN_REFETCH_MS)) {
    await loadKeys();
  }
  return cache?.keys.get(kid);
}

async function loadKeys(): Promise<void> {
  let response: Response;
  try {
    response = await fetch(CERTS_URL);
  } catch {
    throw new ProxyError(503, 'api_error', "Couldn't reach Google to check your sign-in.");
  }
  if (!response.ok) {
    throw new ProxyError(503, 'api_error', "Couldn't reach Google to check your sign-in.");
  }

  const body = (await response.json()) as Jwks;
  const keys = new Map<string, CryptoKey>();
  for (const jwk of body.keys ?? []) {
    if (jwk.kty !== 'RSA' || typeof jwk.kid !== 'string') continue;
    if (jwk.alg && jwk.alg !== 'RS256') continue;
    keys.set(
      jwk.kid,
      await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, [
        'verify',
      ]),
    );
  }

  const maxAge = parseMaxAge(response.headers.get('cache-control')) ?? 3600;
  const now = Date.now();
  cache = { keys, expiresAt: now + maxAge * 1000, fetchedAt: now };
}

export function parseMaxAge(header: string | null): number | null {
  const match = header?.match(/max-age=(\d+)/);
  return match ? Number(match[1]) : null;
}

export function base64UrlToBytes(segment: string): Uint8Array {
  const base64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
  let binary: string;
  try {
    binary = atob(padded);
  } catch {
    throw badToken();
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeSegment(segment: string): Record<string, unknown> {
  try {
    const json = new TextDecoder().decode(base64UrlToBytes(segment));
    const value = JSON.parse(json);
    if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch (e) {
    if (e instanceof ProxyError) throw e;
    throw badToken();
  }
}

/** Reset the JWKS cache. Tests only. */
export function resetKeyCache(): void {
  cache = null;
}
