import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { withErrorHandler } from "@/lib/api-handler";

// L17-01 — outermost safety-net: throws inesperados (Edge Function fetch
// crash, batch job insert race) viram 500 INTERNAL_ERROR canônico em vez
// de stack trace cru.
export const POST = withErrorHandler(_post, "api.billing.batch.post");

async function _post(request: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const athletes = body.athletes as Array<{
    user_id: string;
    subscription_id: string;
    name: string;
    cpf: string;
    email?: string;
  }>;

  if (!athletes?.length) {
    return NextResponse.json({ error: "athletes required" }, { status: 400 });
  }

  const db = createServiceClient();

  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership || !["admin_master", "coach"].includes(membership.role)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  // Create batch job record for tracking
  const { data: batchJob, error: bjErr } = await db
    .from("billing_batch_jobs")
    .insert({
      group_id: groupId,
      plan_id: body.plan_id,
      athlete_ids: athletes.map((a) => a.user_id),
      total: athletes.length,
      status: "pending",
      created_by: user.id,
    })
    .select("id")
    .single();

  if (bjErr || !batchJob) {
    return NextResponse.json(
      { error: `Failed to create batch job: ${bjErr?.message}` },
      { status: 500 },
    );
  }

  // Forward to Edge Function for server-side processing
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session?.access_token) {
    return NextResponse.json({ error: "Session expired" }, { status: 401 });
  }

  const edgeRes = await fetch(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL!}/functions/v1/asaas-batch`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        group_id: groupId,
        batch_job_id: batchJob.id,
        athletes,
        plan_value: body.plan_value,
        plan_name: body.plan_name,
        billing_cycle: body.billing_cycle,
        next_due_date: body.next_due_date,
      }),
    },
  );

  const result = await edgeRes.json().catch(() => ({}));

  return NextResponse.json(
    { batch_job_id: batchJob.id, ...result },
    { status: edgeRes.status },
  );
}
