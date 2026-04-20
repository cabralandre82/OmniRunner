import { type NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { rateLimit } from "@/lib/rate-limit";
import { withErrorHandler } from "@/lib/api-handler";

// L17-01 — outermost safety-net: throws inesperados (fetch crash,
// session JSON parse, supabase auth client crash) viram 500 INTERNAL_ERROR
// canônico em vez de stack trace cru.
export const POST = withErrorHandler(_post, "api.billing-portal.post");

async function _post(_request: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = await rateLimit(`billing-portal:${user.id}`, { maxRequests: 5, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  const { data: { session } } = await supabase.auth.getSession();
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const res = await fetch(
    `${supabaseUrl}/functions/v1/create-portal-session`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session?.access_token}`,
      },
      body: JSON.stringify({ group_id: groupId }),
    },
  );

  const data = await res.json();

  if (!res.ok || !data.ok) {
    return NextResponse.json(
      { error: data.error?.message ?? "Failed to open billing portal" },
      { status: res.status },
    );
  }

  return NextResponse.json({ portal_url: data.portal_url });
}
