import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function POST(req: Request) {
  try {
    const { member_id, watch_type } = (await req.json()) as {
      member_id: string;
      watch_type: string | null;
    };

    if (!member_id) {
      return NextResponse.json({ error: "Missing member_id" }, { status: 400 });
    }

    const supabase = createClient();
    const { data, error } = await supabase.rpc("fn_set_athlete_watch_type", {
      p_member_id: member_id,
      p_watch_type: watch_type ?? "",
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    const res = data as { ok: boolean; code?: string };
    if (!res.ok) {
      return NextResponse.json({ error: res.code }, { status: 403 });
    }

    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
