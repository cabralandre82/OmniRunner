import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { getSettlementsForGroup } from "@/lib/clearing";
import { rateLimit } from "@/lib/rate-limit";
import { logger } from "@/lib/logger";

async function requireStaff() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Não autorizado", status: 401 } as const;

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return { error: "Grupo não selecionado", status: 400 } as const;

  const db = createServiceClient();
  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (
    !callerMembership ||
    !["admin_master", "coach"].includes(
      (callerMembership as { role: string }).role
    )
  ) {
    return { error: "Sem permissão", status: 403 } as const;
  }

  return { user, groupId } as const;
}

export async function GET(req: NextRequest) {
  try {
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
  } catch (error) {
    logger.error("Failed to fetch clearing settlements", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}
