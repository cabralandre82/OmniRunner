import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function POST(req: Request) {
  try {
    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "No group" }, { status: 400 });
    }

    const body = await req.json();
    const { template_id, athlete_user_ids, scheduled_date } = body as {
      template_id: string;
      athlete_user_ids: string[];
      scheduled_date: string;
    };

    if (!template_id || !athlete_user_ids?.length || !scheduled_date) {
      return NextResponse.json(
        { error: "Missing fields" },
        { status: 400 }
      );
    }

    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
    }

    const results: { userId: string; ok: boolean; message?: string }[] = [];

    for (const userId of athlete_user_ids) {
      const { data, error } = await supabase.rpc("fn_assign_workout", {
        p_template_id: template_id,
        p_athlete_user_id: userId,
        p_scheduled_date: scheduled_date,
      });

      if (error) {
        results.push({ userId, ok: false, message: error.message });
      } else {
        const res = data as { ok: boolean; code?: string; message?: string };
        results.push({
          userId,
          ok: res.ok,
          message: res.message ?? res.code,
        });
      }
    }

    const successCount = results.filter((r) => r.ok).length;
    return NextResponse.json({
      ok: successCount > 0,
      total: athlete_user_ids.length,
      success: successCount,
      results,
    });
  } catch (e) {
    return NextResponse.json(
      { error: String(e) },
      { status: 500 }
    );
  }
}
