import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { handleCors } from "../_shared/cors.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";

const ASAAS_SANDBOX = "https://api-sandbox.asaas.com/v3";
const ASAAS_PROD = "https://api.asaas.com/v3";

function asaasBase(env: string): string {
  return env === "production" ? ASAAS_PROD : ASAAS_SANDBOX;
}

async function asaasFetch(
  baseUrl: string,
  apiKey: string,
  path: string,
  method: string,
  body?: Record<string, unknown>,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { "Content-Type": "application/json", access_token: apiKey },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  return { ok: res.ok, status: res.status, data };
}

interface AthleteInput {
  user_id: string;
  subscription_id: string;
  name: string;
  cpf: string;
  email?: string;
}

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;
  const rid = crypto.randomUUID();

  let auth;
  try {
    auth = await requireUser(req);
  } catch (e) {
    if (e instanceof AuthError) return jsonErr(e.status, "AUTH", e.message, rid, undefined, undefined, req);
    return jsonErr(500, "INTERNAL", "Auth failed", rid, undefined, undefined, req);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonErr(400, "BAD_REQUEST", "Invalid JSON", rid, undefined, undefined, req);
  }

  const groupId = body.group_id as string;
  const batchJobId = body.batch_job_id as string;
  const athletes = body.athletes as AthleteInput[];
  const planValue = body.plan_value as number;
  const planName = body.plan_name as string;
  const billingCycle = (body.billing_cycle as string) ?? "MONTHLY";
  const nextDueDate = body.next_due_date as string;

  if (!groupId || !athletes?.length || !planValue || !nextDueDate) {
    return jsonErr(400, "BAD_REQUEST", "group_id, athletes, plan_value, next_due_date required", rid, undefined, undefined, req);
  }

  const db = auth.adminDb;

  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", auth.user.id)
    .single();

  if (!membership || !["admin_master", "coach"].includes(membership.role)) {
    return jsonErr(403, "FORBIDDEN", "Not authorized", rid, undefined, undefined, req);
  }

  const { data: config } = await db
    .from("payment_provider_config")
    .select("api_key, environment")
    .eq("group_id", groupId)
    .eq("provider", "asaas")
    .eq("is_active", true)
    .maybeSingle();

  if (!config) {
    return jsonErr(404, "NO_CONFIG", "Asaas not active", rid, undefined, undefined, req);
  }

  const apiKey = config.api_key as string;
  const base = asaasBase(config.environment as string);

  const { data: feeRow } = await db
    .from("platform_fee_config")
    .select("rate_pct")
    .eq("fee_type", "billing_split")
    .eq("is_active", true)
    .maybeSingle();
  const splitPct = feeRow?.rate_pct ? Number(feeRow.rate_pct) : 2.5;
  const omniWalletId = Deno.env.get("ASAAS_OMNI_WALLET_ID") ?? "";

  // Mark batch as processing
  if (batchJobId) {
    await db
      .from("billing_batch_jobs")
      .update({ status: "processing" })
      .eq("id", batchJobId);
  }

  const results: { user_id: string; ok: boolean; step: string; error?: string }[] = [];
  let succeeded = 0;

  for (const athlete of athletes) {
    try {
      // 1. Ensure Asaas customer
      const { data: existingCust } = await db
        .from("asaas_customer_map")
        .select("asaas_customer_id")
        .eq("group_id", groupId)
        .eq("athlete_user_id", athlete.user_id)
        .maybeSingle();

      let asaasCustomerId: string;

      if (existingCust) {
        asaasCustomerId = existingCust.asaas_customer_id;
      } else {
        let email = athlete.email;
        if (!email) {
          const { data: authUser } = await db.auth.admin.getUserById(athlete.user_id);
          email = authUser?.user?.email ?? "";
        }

        const custRes = await asaasFetch(base, apiKey, "/customers", "POST", {
          name: athlete.name,
          cpfCnpj: athlete.cpf.replace(/\D/g, ""),
          email: email || undefined,
          externalReference: athlete.user_id,
          notificationDisabled: false,
        });

        if (!custRes.ok) {
          results.push({ user_id: athlete.user_id, ok: false, step: "create_customer", error: JSON.stringify(custRes.data) });
          continue;
        }

        asaasCustomerId = custRes.data.id as string;

        await db.from("asaas_customer_map").upsert(
          { group_id: groupId, athlete_user_id: athlete.user_id, asaas_customer_id: asaasCustomerId },
          { onConflict: "group_id,athlete_user_id", ignoreDuplicates: true },
        );

        await db.from("coaching_members")
          .update({ cpf: athlete.cpf.replace(/\D/g, "") })
          .eq("group_id", groupId)
          .eq("user_id", athlete.user_id)
          .is("cpf", null);
      }

      // 2. Check if subscription already mapped
      const { data: existingSub } = await db
        .from("asaas_subscription_map")
        .select("asaas_subscription_id")
        .eq("subscription_id", athlete.subscription_id)
        .maybeSingle();

      if (existingSub) {
        results.push({ user_id: athlete.user_id, ok: true, step: "already_exists" });
        succeeded++;
        continue;
      }

      // 3. Create Asaas subscription
      const splitConfig = omniWalletId
        ? [{ walletId: omniWalletId, percentualValue: splitPct }]
        : undefined;

      const cycle = billingCycle === "quarterly" ? "QUARTERLY" : "MONTHLY";

      const subRes = await asaasFetch(base, apiKey, "/subscriptions", "POST", {
        customer: asaasCustomerId,
        billingType: "UNDEFINED",
        value: planValue,
        nextDueDate,
        cycle,
        description: `${planName ?? "Plano"} — ${athlete.name}`,
        externalReference: athlete.subscription_id,
        ...(splitConfig ? { split: splitConfig } : {}),
      });

      if (!subRes.ok) {
        results.push({ user_id: athlete.user_id, ok: false, step: "create_subscription", error: JSON.stringify(subRes.data) });
        continue;
      }

      await db.from("asaas_subscription_map").upsert(
        {
          subscription_id: athlete.subscription_id,
          asaas_subscription_id: subRes.data.id as string,
          asaas_status: (subRes.data.status as string) ?? "ACTIVE",
          group_id: groupId,
        },
        { onConflict: "subscription_id", ignoreDuplicates: true },
      );

      results.push({ user_id: athlete.user_id, ok: true, step: "completed" });
      succeeded++;
    } catch (e) {
      results.push({
        user_id: athlete.user_id,
        ok: false,
        step: "exception",
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  // Mark batch as completed
  if (batchJobId) {
    await db
      .from("billing_batch_jobs")
      .update({
        status: succeeded === athletes.length ? "completed" : "completed",
        succeeded,
        failed: athletes.length - succeeded,
        results: JSON.stringify(results),
        completed_at: new Date().toISOString(),
      })
      .eq("id", batchJobId);
  }

  return jsonOk({
    total: athletes.length,
    succeeded,
    failed: athletes.length - succeeded,
    results,
  }, rid, req);
});
