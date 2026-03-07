import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { logger } from "@/lib/logger";

export async function GET() {
  try {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = await rateLimit(`export:${user.id}`, { maxRequests: 3, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 400 });
  }

  const db = createServiceClient();

  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (
    !callerMembership ||
    !["admin_master", "coach"].includes(callerMembership.role)
  ) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { data: members } = await db
    .from("coaching_members")
    .select("id, display_name, email, role, joined_at_ms")
    .eq("group_id", groupId)
    .order("display_name");

  const allMembers = members ?? [];

  const roleLabels: Record<string, string> = {
    admin_master: "Admin",
    coach: "Coach",
    assistant: "Assistente",
    athlete: "Atleta",
  };

  const BOM = "\uFEFF";
  const header = "Nome,Email,Função,Membro desde";
  const rows = allMembers.map((m: { id: string; display_name: string; email: string | null; role: string; joined_at_ms: number }) => {
    const name = (m.display_name || "Sem nome").replace(/,/g, " ");
    const email = (m.email ?? "").replace(/,/g, " ");
    const role = roleLabels[m.role] ?? m.role;
    const joined = new Date(m.joined_at_ms).toLocaleDateString("pt-BR");
    return `${name},${email},${role},${joined}`;
  });

  const csv = BOM + header + "\n" + rows.join("\n");

  await auditLog({
    actorId: user.id,
    groupId,
    action: "export.athletes_csv",
    metadata: { count: allMembers.length },
  });

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="atletas_${new Date().toISOString().slice(0, 10)}.csv"`,
    },
  });
  } catch (error) {
    logger.error("Failed to export athletes CSV", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}
