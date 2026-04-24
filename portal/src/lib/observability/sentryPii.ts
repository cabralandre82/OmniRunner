/**
 * Sentry PII guard (L04-13).
 *
 * Sentry's default behaviour ("send default PII") attaches:
 *   - `event.user.ip_address`     — derived from the request socket
 *   - `event.user.email`          — set by `Sentry.setUser({ email })`
 *   - `event.request.headers`     — Authorization, Cookie, x-forwarded-for, ...
 *   - `event.request.query_string`— URL params (?email=...&token=...)
 *   - `event.request.cookies`     — full Cookie header parsed
 *   - `event.contexts.request.client_ip`
 *
 * The portal explicitly disables `sendDefaultPii` in every Sentry.init,
 * but a legacy `Sentry.setUser({ email })` call OR a future SDK upgrade
 * could re-introduce the leak. `stripPii` is the last line of defence:
 * it runs in `beforeSend` / `beforeSendTransaction` and unconditionally
 * removes everything in the list above.
 *
 * `user.id` is *retained*. We need it for incident triage (which user
 * hit this error?) and the LGPD risk is acceptable: a UUID is a
 * pseudonymous identifier, not direct PII. If we ever need to delete a
 * user's logs entirely, we can purge by `user.id` via the Sentry API.
 *
 * Tests: see `sentryPii.test.ts`.
 */

import type { ErrorEvent, EventHint, TransactionEvent } from "@sentry/core";

type AnyEvent = ErrorEvent | TransactionEvent;

export function stripPii<E extends AnyEvent | null>(
  event: E,
  _hint?: EventHint,
): E {
  if (!event) return event;

  // user: keep id only.
  if (event.user) {
    const safeUser: { id?: string | number } = {};
    if (event.user.id !== undefined) safeUser.id = event.user.id;
    event.user = safeUser;
  }

  // request: drop cookies, headers, query string, body data.
  if (event.request) {
    if ("cookies" in event.request) {
      delete event.request.cookies;
    }
    if ("headers" in event.request && event.request.headers) {
      // Drop Authorization / Cookie / x-forwarded-for / x-real-ip.
      // Allow only a small allow-list useful for triage.
      const allowed = new Set([
        "user-agent",
        "x-request-id",
        "x-omni-client",
        "referer",
      ]);
      const filtered: Record<string, string> = {};
      for (const [k, v] of Object.entries(event.request.headers)) {
        if (allowed.has(k.toLowerCase()) && typeof v === "string") {
          filtered[k] = v;
        }
      }
      event.request.headers = filtered;
    }
    if ("query_string" in event.request) {
      delete event.request.query_string;
    }
    if ("data" in event.request) {
      delete event.request.data;
    }
  }

  // contexts.request.client_ip (some SDKs put it here too).
  const reqCtx = event.contexts?.request as
    | { client_ip?: string }
    | undefined;
  if (reqCtx && "client_ip" in reqCtx) {
    delete reqCtx.client_ip;
  }

  return event;
}
