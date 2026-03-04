import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";

export async function GET() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`export:${user.id}`, { maxRequests: 3, windowMs: 60_000 });
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

  const { data: entries } = await db
    .from("coaching_financial_ledger")
    .select("created_at, type, category, amount, description")
    .eq("group_id", groupId)
    .order("created_at", { ascending: false });

  const allEntries = entries ?? [];

  const BOM = "\uFEFF";
  const header = "Data,Tipo,Categoria,Valor,Descrição";
  const rows = allEntries.map(
    (e: {
      created_at: string;
      type: string;
      category: string;
      amount: number;
      description: string | null;
    }) => {
      const date = new Date(e.created_at).toLocaleDateString("pt-BR");
      const desc = (e.description ?? "").replace(/,/g, " ");
      return `${date},${e.type},${e.category},${e.amount.toFixed(2)},${desc}`;
    },
  );

  const csv = BOM + header + "\n" + rows.join("\n");

  await auditLog({
    actorId: user.id,
    groupId,
    action: "export.financial_ledger_csv",
    metadata: { count: allEntries.length },
  });

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="financeiro_${new Date().toISOString().slice(0, 10)}.csv"`,
    },
  });
}
