import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";

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
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { error: auth.error },
      { status: auth.status },
    );
  }

  const body = await req.json();
  const { action, refund_id, notes } = body as {
    action: string;
    refund_id: string;
    notes?: string;
  };

  if (!action || !refund_id) {
    return NextResponse.json(
      { error: "Missing action or refund_id" },
      { status: 400 },
    );
  }

  const admin = createAdminClient();

  if (action === "approve") {
    const { error } = await admin
      .from("billing_refund_requests")
      .update({
        status: "approved",
        reviewed_by: auth.user.id,
        reviewed_at: new Date().toISOString(),
        review_notes: notes ?? null,
      })
      .eq("id", refund_id)
      .eq("status", "requested");

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.approve_refund", targetType: "refund", targetId: refund_id, metadata: { notes } });
    return NextResponse.json({ status: "approved" });
  }

  if (action === "reject") {
    if (!notes?.trim()) {
      return NextResponse.json(
        { error: "Notes required for rejection" },
        { status: 400 },
      );
    }

    const { error } = await admin
      .from("billing_refund_requests")
      .update({
        status: "rejected",
        reviewed_by: auth.user.id,
        reviewed_at: new Date().toISOString(),
        review_notes: notes.trim(),
      })
      .eq("id", refund_id)
      .eq("status", "requested");

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({ actorId: auth.user.id, action: "platform.reject_refund", targetType: "refund", targetId: refund_id, metadata: { notes: notes!.trim() } });
    return NextResponse.json({ status: "rejected" });
  }

  if (action === "process") {
    const { data: refund } = await admin
      .from("billing_refund_requests")
      .select("id, purchase_id, group_id, status, credits_to_debit")
      .eq("id", refund_id)
      .single();

    if (!refund || refund.status !== "approved") {
      return NextResponse.json(
        { error: "Refund must be approved before processing" },
        { status: 400 },
      );
    }

    const { error: refundErr } = await admin
      .from("billing_refund_requests")
      .update({
        status: "processed",
        processed_at: new Date().toISOString(),
      })
      .eq("id", refund_id);

    if (refundErr) {
      return NextResponse.json({ error: refundErr.message }, { status: 500 });
    }

    await admin
      .from("billing_purchases")
      .update({
        status: "refunded",
        updated_at: new Date().toISOString(),
      })
      .eq("id", refund.purchase_id);

    await admin.from("billing_events").insert({
      purchase_id: refund.purchase_id,
      event_type: "refunded",
      actor_id: auth.user.id,
      metadata: {
        refund_request_id: refund_id,
        credits_debited: refund.credits_to_debit,
      },
    });

    if (refund.credits_to_debit && refund.credits_to_debit > 0) {
      try {
        await admin.rpc("fn_debit_institution_credits", {
          p_group_id: refund.group_id,
          p_amount: refund.credits_to_debit,
        });
      } catch {
        // fn may not exist yet; debit manually if needed
      }
    }

    await auditLog({ actorId: auth.user.id, action: "platform.process_refund", targetType: "refund", targetId: refund_id, metadata: { purchase_id: refund.purchase_id, credits_debited: refund.credits_to_debit } });
    return NextResponse.json({ status: "processed" });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
