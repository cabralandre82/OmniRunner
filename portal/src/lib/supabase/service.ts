// Service-role client — bypasses RLS, used for cross-user writes.
// Use in API routes that need to read/write across multiple users
// (e.g. batch operations, cron-triggered tasks).
// Prefer createClient() when the operation is user-scoped.
//
// L02-11 — module-cached singleton.
//
// Each Supabase client opens its own keep-alive HTTP socket pool to
// PostgREST. In Vercel Serverless a single warm instance can fire
// hundreds of `createServiceClient()` calls per minute (every API
// route helper builds one). Without the cache each call builds a
// fresh client, fresh socket pool, fresh AbortController plumbing —
// no pooling at all. Under load that throws transient ECONNRESET
// against PostgREST and adds 5-15 ms of TLS handshake latency per
// call.
//
// We cache the client at module scope so the **same warm lambda**
// reuses the same client across requests. Cold starts pay one
// construction cost. Tests can call `__resetServiceClientForTests`
// to drop the singleton between mocks.

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

const SUPABASE_FETCH_TIMEOUT_MS = 15_000;

type ServiceClient = ReturnType<typeof createSupabaseClient>;

let _client: ServiceClient | null = null;
let _configKey = "";

function buildClient(): ServiceClient {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: (url, options) => {
          const controller = new AbortController();
          const timer = setTimeout(
            () => controller.abort(),
            SUPABASE_FETCH_TIMEOUT_MS,
          );
          const merged = options?.signal
            ? options
            : { ...options, signal: controller.signal };
          return fetch(url, { ...merged, cache: "no-store" }).finally(() =>
            clearTimeout(timer),
          );
        },
      },
    },
  );
}

export function createServiceClient(): ServiceClient {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  // Re-build when config changes (test rotation, secret rotation
  // landing while the lambda is warm). The key incorporates the
  // length of the secret rather than the value itself so the module
  // never holds the secret in plaintext after process restart.
  const configKey = `${url}::${key.length}`;
  if (_client && configKey === _configKey) {
    return _client;
  }
  _client = buildClient();
  _configKey = configKey;
  return _client;
}

/**
 * Test-only hook: drop the cached singleton so the next
 * createServiceClient() call rebuilds (typically used together with a
 * fresh process.env mock).
 *
 * @internal
 */
export function __resetServiceClientForTests(): void {
  _client = null;
  _configKey = "";
}
