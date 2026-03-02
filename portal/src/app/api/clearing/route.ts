import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { getSettlementsForGroup } from "@/lib/clearing";
import { rateLimit } from "@/lib/rate-limit";

async function requireStaff() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Unauthorized", status: 401 } as const;

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return { error: "No group", status: 400 } as const;

  const db = createServiceClient();
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership || !["admin_master", "professor"].includes(membership.role)) {
    return { error: "Forbidden", status: 403 } as const;
  }

  return { user, groupId } as const;
}

export async function GET(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = rateLimit(`clearing:${ip}`, { maxRequests: 30, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requireStaff();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const role =
    (req.nextUrl.searchParams.get("role") as "creditor" | "debtor") || "both";

  const settlements = await getSettlementsForGroup(auth.groupId, role);
  return NextResponse.json({ settlements });
}
