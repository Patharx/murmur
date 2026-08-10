import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { ProxyError } from '../src/errors';
import { base64UrlToBytes, bearerToken, parseMaxAge, resetKeyCache, verifyGoogleIdToken } from '../src/google';

const AUDIENCE = '1234567890-abcdef.apps.googleusercontent.com';
const KID = 'test-kid';

let privateKey: CryptoKey;
let publicJwk: JsonWebKey & { kid: string };

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;

  privateKey = pair.privateKey;
  // exportKey is typed as ArrayBuffer | JsonWebKey; the 'jwk' format gives the latter.
  const exported = (await crypto.subtle.exportKey('jwk', pair.publicKey)) as JsonWebKey;
  publicJwk = { ...exported, kid: KID };
});

afterEach(() => {
  resetKeyCache();
  vi.unstubAllGlobals();
});

function encodeSegment(value: unknown): string {
  return bytesToBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function makeToken(claims: Record<string, unknown>, header: Record<string, unknown> = {}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const head = encodeSegment({ alg: 'RS256', kid: KID, typ: 'JWT', ...header });
  const payload = encodeSegment({
    iss: 'https://accounts.google.com',
    aud: AUDIENCE,
    sub: '110000000000000000001',
    iat: now,
    exp: now + 3600,
    ...claims,
  });
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(`${head}.${payload}`) as BufferSource,
  );
  return `${head}.${payload}.${bytesToBase64Url(new Uint8Array(signature))}`;
}

function stubCerts(keys: unknown[] = [publicJwk]) {
  const fetchMock = vi.fn(
    async () =>
      new Response(JSON.stringify({ keys }), {
        headers: { 'cache-control': 'public, max-age=3600' },
      }),
  );
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

async function expectRejected(token: string): Promise<ProxyError> {
  try {
    await verifyGoogleIdToken(token, [AUDIENCE]);
  } catch (e) {
    expect(e).toBeInstanceOf(ProxyError);
    return e as ProxyError;
  }
  throw new Error('expected the token to be rejected');
}

describe('verifyGoogleIdToken', () => {
  it('returns the sub for a well-formed token', async () => {
    stubCerts();
    const sub = await verifyGoogleIdToken(await makeToken({}), [AUDIENCE]);
    expect(sub).toBe('110000000000000000001');
  });

  it('accepts the bare accounts.google.com issuer too', async () => {
    stubCerts();
    const sub = await verifyGoogleIdToken(await makeToken({ iss: 'accounts.google.com' }), [AUDIENCE]);
    expect(sub).toBe('110000000000000000001');
  });

  it('accepts any of several configured audiences', async () => {
    stubCerts();
    const sub = await verifyGoogleIdToken(await makeToken({}), ['other.apps.googleusercontent.com', AUDIENCE]);
    expect(sub).toBe('110000000000000000001');
  });

  it('caches the certs rather than fetching per request', async () => {
    const fetchMock = stubCerts();
    await verifyGoogleIdToken(await makeToken({}), [AUDIENCE]);
    await verifyGoogleIdToken(await makeToken({}), [AUDIENCE]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('rejects a token for a different audience', async () => {
    stubCerts();
    const e = await expectRejected(await makeToken({ aud: 'someone-else.apps.googleusercontent.com' }));
    expect(e.status).toBe(401);
  });

  it('rejects a token from a different issuer', async () => {
    stubCerts();
    const e = await expectRejected(await makeToken({ iss: 'https://evil.example.com' }));
    expect(e.status).toBe(401);
  });

  it('rejects an expired token', async () => {
    stubCerts();
    const now = Math.floor(Date.now() / 1000);
    const e = await expectRejected(await makeToken({ iat: now - 7200, exp: now - 3600 }));
    expect(e.status).toBe(401);
  });

  it('rejects a token whose payload was swapped after signing', async () => {
    stubCerts();
    const token = await makeToken({});
    const [head, , signature] = token.split('.');
    const forged = encodeSegment({
      iss: 'https://accounts.google.com',
      aud: AUDIENCE,
      sub: 'someone-elses-notebook',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });
    const e = await expectRejected(`${head}.${forged}.${signature}`);
    expect(e.status).toBe(401);
  });

  it('rejects an unsigned (alg: none) token', async () => {
    stubCerts();
    const head = encodeSegment({ alg: 'none', kid: KID, typ: 'JWT' });
    const payload = encodeSegment({
      iss: 'https://accounts.google.com',
      aud: AUDIENCE,
      sub: 'x',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });
    const e = await expectRejected(`${head}.${payload}.`);
    expect(e.status).toBe(401);
  });

  it('rejects a token signed with a key Google does not publish', async () => {
    stubCerts([]); // certs endpoint returns no keys
    const e = await expectRejected(await makeToken({}));
    expect(e.status).toBe(401);
  });

  it('rejects something that is not a JWT at all', async () => {
    stubCerts();
    const e = await expectRejected('not-a-token');
    expect(e.status).toBe(401);
  });

  it('surfaces a reachability problem as 503, not as a bad sign-in', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response('nope', { status: 500 })),
    );
    const e = await expectRejected(await makeToken({}));
    expect(e.status).toBe(503);
  });
});

describe('bearerToken', () => {
  it('reads the token out of the header', () => {
    expect(bearerToken('Bearer abc.def.ghi')).toBe('abc.def.ghi');
  });

  it('rejects a missing header', () => {
    expect(() => bearerToken(null)).toThrow(ProxyError);
  });

  it('rejects a non-bearer scheme', () => {
    expect(() => bearerToken('Basic abc')).toThrow(ProxyError);
  });
});

describe('helpers', () => {
  it('decodes base64url without padding', () => {
    expect(new TextDecoder().decode(base64UrlToBytes('aGVsbG8'))).toBe('hello');
  });

  it('round-trips non-ASCII payloads as UTF-8', () => {
    const text = 'my father’s garden — rows';
    expect(new TextDecoder().decode(base64UrlToBytes(bytesToBase64Url(new TextEncoder().encode(text))))).toBe(text);
  });

  it('reads max-age out of a cache-control header', () => {
    expect(parseMaxAge('public, max-age=19273, must-revalidate')).toBe(19273);
    expect(parseMaxAge(null)).toBeNull();
    expect(parseMaxAge('no-store')).toBeNull();
  });
});
