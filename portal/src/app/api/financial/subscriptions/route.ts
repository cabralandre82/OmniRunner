import { type NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { withErrorHandler } from "@/lib/api-handler";

// L17-01 — outermost safety-net: throws inesperados (DB outage, JSON
// parse) viram 500 INTERNAL_ERROR canônico em vez do legado
// `{ error: String(e) }` que vazava raw error messages.
export const POST = withErrorHandler(_post, "api.financial.subscriptions.post");

async function _post(req: NextRequest) {
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 400 });
  }

  const body = await req.json();
  const { plan_id, athlete_user_ids, started_at, next_due_date } = body as {
    plan_id: string;
    athlete_user_ids: string[];
    started_at: string;
    next_due_date: string;
  };

  if (!plan_id || !athlete_user_ids?.length || !started_at || !next_due_date) {
    return NextResponse.json({ error: "Campos obrigatórios faltando" }, { status: 400 });
  }

  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const results: { userId: string; ok: boolean; message?: string }[] = [];

  const subscriptionIds: Record<string, string> = {};

  for (const userId of athlete_user_ids) {
    const { data, error } = await supabase
      .from("coaching_subscriptions")
      .upsert(
        {
          group_id: groupId,
          athlete_user_id: userId,
          plan_id,
          status: "active",
          started_at,
          next_due_date,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "athlete_user_id,group_id" },
      )
      .select("id")
      .single();

    if (error) {
      results.push({ userId, ok: false, message: error.message });
    } else {
      results.push({ userId, ok: true });
      if (data?.id) subscriptionIds[userId] = data.id;
    }
  }

  const successCount = results.filter((r) => r.ok).length;
  return NextResponse.json({
    ok: successCount > 0,
    total: athlete_user_ids.length,
    success: successCount,
    subscription_ids: subscriptionIds,
    results,
  });
}
