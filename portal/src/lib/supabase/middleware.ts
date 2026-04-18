import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refresh the Supabase session from a Next.js middleware. Returns the
 * resolved `user`, the response (with refreshed auth cookies), and the
 * Supabase client.
 *
 * `extraRequestHeaders` is appended to the request headers that flow
 * downstream to RSCs / API handlers (L13-06). The portal's middleware
 * uses this to propagate `x-request-id` to downstream code that calls
 * `headers().get("x-request-id")`.
 */
export async function updateSession(
  request: NextRequest,
  extraRequestHeaders?: Readonly<Record<string, string>>,
) {
  const requestHeaders = extraRequestHeaders
    ? new Headers(request.headers)
    : null;
  if (requestHeaders) {
    for (const [key, value] of Object.entries(extraRequestHeaders!)) {
      requestHeaders.set(key, value);
    }
  }

  const buildResponse = () =>
    requestHeaders
      ? NextResponse.next({ request: { headers: requestHeaders } })
      : NextResponse.next({ request });

  let supabaseResponse = buildResponse();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          supabaseResponse = buildResponse();
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  return { user, supabaseResponse, supabase };
}
