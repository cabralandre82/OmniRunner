// Client selection rules:
// - createClient() — user-scoped server client. Use for reads that should respect RLS.
// - createServiceClient() — service-role client. Use for writes that need to cross user boundaries.
// - createAdminClient() — admin client. Use for platform admin operations (e.g. /platform/* pages).

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// NOTE (M12): @supabase/ssr's createServerClient does not support a custom
// `global.fetch` for timeout injection. Per-request timeout must be applied at
// the call site. This is a supabase-js SSR SDK limitation.
export function createClient() {
  const cookieStore = cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Called from Server Component — ignore
          }
        },
      },
    },
  );
}
