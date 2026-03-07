import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
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
  const rl = await rateLimit(`platform-support:${ip}`, { maxRequests: 20, windowMs: 60_000 });
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
  const { action, ticket_id, message } = body as {
    action: string;
    ticket_id: string;
    message?: string;
  };

  if (!action || !ticket_id) {
    return NextResponse.json(
      { error: "Missing action or ticket_id" },
      { status: 400 },
    );
  }

  const admin = createAdminClient();

  if (action === "reply") {
    if (!message?.trim()) {
      return NextResponse.json(
        { error: "Message is required" },
        { status: 400 },
      );
    }

    const { error: msgErr } = await admin.from("support_messages").insert({
      ticket_id,
      sender_id: auth.user.id,
      sender_role: "platform",
      body: message.trim(),
    });

    if (msgErr) {
      return NextResponse.json({ error: msgErr.message }, { status: 500 });
    }

    const { error: ticketErr } = await admin
      .from("support_tickets")
      .update({ status: "answered" })
      .eq("id", ticket_id);

    if (ticketErr) {
      return NextResponse.json({ error: ticketErr.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.reply_ticket", targetType: "ticket", targetId: ticket_id });
    return NextResponse.json({ status: "replied", ticket_id });
  }

  if (action === "close") {
    const { error } = await admin
      .from("support_tickets")
      .update({ status: "closed" })
      .eq("id", ticket_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.close_ticket", targetType: "ticket", targetId: ticket_id });
    return NextResponse.json({ status: "closed", ticket_id });
  }

  if (action === "reopen") {
    const { error } = await admin
      .from("support_tickets")
      .update({ status: "open" })
      .eq("id", ticket_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.reopen_ticket", targetType: "ticket", targetId: ticket_id });
    return NextResponse.json({ status: "reopened", ticket_id });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
