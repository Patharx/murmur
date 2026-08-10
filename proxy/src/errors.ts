// Errors are returned in Anthropic's own error shape so the app has one parser
// for both proxy failures and upstream failures.
//
// Messages here are user-facing. docs/CLAUDE_LAYER.md §5 applies: never use the
// word "error", never blame the user, keep it quiet.

export type ErrorType =
  | 'invalid_request_error'
  | 'authentication_error'
  | 'permission_error'
  | 'not_found_error'
  | 'request_too_large'
  | 'rate_limit_error'
  | 'api_error';

export class ProxyError extends Error {
  constructor(
    readonly status: number,
    readonly type: ErrorType,
    message: string,
  ) {
    super(message);
    this.name = 'ProxyError';
  }
}

export function errorResponse(status: number, type: ErrorType, message: string): Response {
  return new Response(JSON.stringify({ type: 'error', error: { type, message } }), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export function toResponse(e: unknown): Response {
  if (e instanceof ProxyError) return errorResponse(e.status, e.type, e.message);
  // Deliberately generic: whatever went wrong, the note is safe on the phone
  // and the app will queue the request and try again.
  return errorResponse(500, 'api_error', "Couldn't read this one back just now.");
}
