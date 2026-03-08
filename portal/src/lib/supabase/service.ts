// Service-role client — bypasses RLS, used for cross-user writes.
// Use in API routes that need to read/write across multiple users
// (e.g. batch operations, cron-triggered tasks).
// Prefer createClient() when the operation is user-scoped.

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

const SUPABASE_FETCH_TIMEOUT_MS = 15_000;

export function createServiceClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: (url, options) => {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), SUPABASE_FETCH_TIMEOUT_MS);
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
