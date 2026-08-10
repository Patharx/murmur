import { describe, expect, it } from 'vitest';
import { ProxyError } from '../src/errors';
import { MAX_TOKENS_CAP, normaliseRequest } from '../src/policy';

const gist = () => ({
  model: 'claude-haiku-4-5',
  max_tokens: 300,
  system: [{ type: 'text', text: 'You are reading back a person’s private notebook to them.' }],
  messages: [{ role: 'user', content: 'Walking past the allotments on Wren Street...' }],
});

function rejection(body: unknown): ProxyError {
  try {
    normaliseRequest(body);
  } catch (e) {
    expect(e).toBeInstanceOf(ProxyError);
    return e as ProxyError;
  }
  throw new Error('expected the request to be rejected');
}

describe('normaliseRequest', () => {
  it('passes a note-gist request through untouched', () => {
    const input = gist();
    const { body, model, stream } = normaliseRequest(input);
    expect(model).toBe('claude-haiku-4-5');
    expect(stream).toBe(false);
    expect(body).toEqual(input);
  });

  it('runs the weekly recap and Ask on the same model', () => {
    const recap = { ...gist(), model: 'claude-haiku-4-5', max_tokens: 400 };
    expect(normaliseRequest(recap).model).toBe('claude-haiku-4-5');
  });

  it('refuses any model but Haiku, however capable', () => {
    expect(rejection({ ...gist(), model: 'claude-sonnet-5' }).status).toBe(403);
    expect(rejection({ ...gist(), model: 'claude-opus-5' }).status).toBe(403);
    expect(rejection({ ...gist(), model: 'claude-haiku-4-5-20251001' }).status).toBe(403);
  });

  it('clamps max_tokens rather than refusing the request', () => {
    const { body } = normaliseRequest({ ...gist(), max_tokens: 999_999 });
    expect(body.max_tokens).toBe(MAX_TOKENS_CAP);
  });

  it('leaves a sane max_tokens alone', () => {
    expect(normaliseRequest({ ...gist(), max_tokens: 300 }).body.max_tokens).toBe(300);
  });

  it('drops metadata so no user identifier reaches Anthropic', () => {
    const { body } = normaliseRequest({ ...gist(), metadata: { user_id: 'sub-12345' } });
    expect(body).not.toHaveProperty('metadata');
  });

  it('reports streaming so the response can be piped', () => {
    expect(normaliseRequest({ ...gist(), stream: true }).stream).toBe(true);
  });

  it('rejects a body that is not an object', () => {
    expect(rejection('a string').status).toBe(400);
    expect(rejection([gist()]).status).toBe(400);
    expect(rejection(null).status).toBe(400);
  });

  it('rejects a missing or non-integer max_tokens', () => {
    const { max_tokens: _omitted, ...withoutMaxTokens } = gist();
    expect(rejection(withoutMaxTokens).status).toBe(400);
    expect(rejection({ ...gist(), max_tokens: 12.5 }).status).toBe(400);
    expect(rejection({ ...gist(), max_tokens: 0 }).status).toBe(400);
  });

  it('rejects a request with no messages', () => {
    expect(rejection({ ...gist(), messages: [] }).status).toBe(400);
    expect(rejection({ ...gist(), messages: 'hello' }).status).toBe(400);
  });

  it('rejects a non-boolean stream', () => {
    expect(rejection({ ...gist(), stream: 'yes' }).status).toBe(400);
  });

  it('does not mutate the caller’s object', () => {
    const input = { ...gist(), max_tokens: 999_999, metadata: { user_id: 'sub-12345' } };
    normaliseRequest(input);
    expect(input.max_tokens).toBe(999_999);
    expect(input.metadata).toEqual({ user_id: 'sub-12345' });
  });
});
