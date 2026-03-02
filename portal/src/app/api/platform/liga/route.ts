import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { rateLimit } from "@/lib/rate-limit";

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Not authenticated", status: 401 };
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();

  if (profile?.platform_role !== "admin") {
    return { error: "Not a platform admin", status: 403 };
  }

  return { user };
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = rateLimit(`platform-liga:${ip}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { error: auth.error },
      { status: auth.status },
    );
  }

  const body = await req.json();
  const { action } = body as { action: string };

  if (!action) {
    return NextResponse.json({ error: "Missing action" }, { status: 400 });
  }

  const admin = createAdminClient();

  if (action === "create_season") {
    const { name, start_at_ms, end_at_ms } = body as {
      name: string;
      start_at_ms: number;
      end_at_ms: number;
    };

    if (!name || !start_at_ms || !end_at_ms) {
      return NextResponse.json(
        { error: "Missing name, start_at_ms, or end_at_ms" },
        { status: 400 },
      );
    }

    const { data, error } = await admin
      .from("league_seasons")
      .insert({
        name,
        start_at_ms,
        end_at_ms,
        status: "upcoming",
      })
      .select()
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "created", season: data });
  }

  if (action === "activate_season") {
    const { season_id } = body as { season_id: string };
    if (!season_id) {
      return NextResponse.json({ error: "Missing season_id" }, { status: 400 });
    }

    // Deactivate any currently active season
    await admin
      .from("league_seasons")
      .update({ status: "completed" })
      .eq("status", "active");

    const { error } = await admin
      .from("league_seasons")
      .update({ status: "active" })
      .eq("id", season_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Auto-enroll all approved assessorias
    const { data: approvedGroups } = await admin
      .from("coaching_groups")
      .select("id")
      .eq("approval_status", "approved");

    let enrolled = 0;
    for (const g of approvedGroups ?? []) {
      const { error: enrollErr } = await admin
        .from("league_enrollments")
        .upsert(
          { season_id, group_id: g.id },
          { onConflict: "season_id,group_id" },
        );
      if (!enrollErr) enrolled++;
    }

    return NextResponse.json({ status: "activated", season_id, enrolled });
  }

  if (action === "complete_season") {
    const { season_id } = body as { season_id: string };
    if (!season_id) {
      return NextResponse.json({ error: "Missing season_id" }, { status: 400 });
    }

    const { error } = await admin
      .from("league_seasons")
      .update({ status: "completed" })
      .eq("id", season_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "completed", season_id });
  }

  if (action === "trigger_snapshot") {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !serviceKey) {
      return NextResponse.json(
        { error: "Server config missing" },
        { status: 500 },
      );
    }

    const res = await fetch(`${supabaseUrl}/functions/v1/league-snapshot`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
    });

    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
