import { NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { safeNext } from "@/lib/security/safe-next";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  // L01-10 — safeNext rejects protocol-relative URLs, foreign
  // schemes, oversized strings, and characters outside the
  // internal-path allowlist. Anything dodgy falls back to /dashboard.
  const next = safeNext(searchParams.get("next"));

  if (code) {
    const cookieStore = cookies();
    const successRedirect = NextResponse.redirect(`${origin}${next}`);

    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          getAll() {
            return cookieStore.getAll();
          },
          setAll(cookiesToSet) {
            cookiesToSet.forEach(({ name, value, options }) => {
              successRedirect.cookies.set(name, value, options);
            });
          },
        },
      },
    );

    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return successRedirect;
    }

    const msg = encodeURIComponent(error.message || "unknown");
    return NextResponse.redirect(`${origin}/login?error=auth&detail=${msg}`);
  }

  return NextResponse.redirect(`${origin}/login?error=auth&detail=no_code`);
}
