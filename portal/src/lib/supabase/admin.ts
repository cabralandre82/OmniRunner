// Platform admin client — bypasses RLS entirely.
// Use ONLY in /platform/* pages and platform admin API routes.
// Never use for assessoria-scoped operations.

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

const SUPABASE_FETCH_TIMEOUT_MS = 15_000;

export function createAdminClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      global: {
        fetch: (url, options) => {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), SUPABASE_FETCH_TIMEOUT_MS);
          const merged = options?.signal
            ? options
            : { ...options, signal: controller.signal };
          return fetch(url, merged).finally(() => clearTimeout(timer));
        },
      },
    },
  );
}
