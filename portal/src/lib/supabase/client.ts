"use client";

import { createBrowserClient } from "@supabase/ssr";

// NOTE (M12): @supabase/ssr's createBrowserClient does not support a custom
// `global.fetch` option, so per-request timeout must be applied at the call
// site (e.g. via AbortController). This is a supabase-js SSR SDK limitation.
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
