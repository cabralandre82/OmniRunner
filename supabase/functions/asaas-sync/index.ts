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
    headers: {
      "Content-Type": "application/json",
      access_token: apiKey,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  return { ok: res.ok, status: res.status, data };
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
    return jsonErr(400, "BAD_REQUEST", "Invalid JSON body", rid, undefined, undefined, req);
  }

  const action = body.action as string;
  const groupId = body.group_id as string;

  if (!action || !groupId) {
    return jsonErr(400, "BAD_REQUEST", "action and group_id required", rid, undefined, undefined, req);
  }

  const db = auth.adminDb;

  // Verify caller is admin_master for this group
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", auth.user.id)
    .single();

  if (!membership || !["admin_master", "coach"].includes(membership.role)) {
    return jsonErr(403, "FORBIDDEN", "Not authorized", rid, undefined, undefined, req);
  }

  // Get provider config
  const { data: config } = await db
    .from("payment_provider_config")
    .select("*")
    .eq("group_id", groupId)
    .eq("provider", "asaas")
    .maybeSingle();

  if (!config && action !== "test_connection") {
    return jsonErr(404, "NO_CONFIG", "Asaas not configured for this group", rid, undefined, undefined, req);
  }

  const apiKey = config?.api_key as string;
  const base = asaasBase(config?.environment as string ?? "sandbox");

  // Get platform split percentage
  const { data: feeRow } = await db
    .from("platform_fee_config")
    .select("rate_pct")
    .eq("fee_type", "billing_split")
    .eq("is_active", true)
    .maybeSingle();

  const splitPct = feeRow?.rate_pct ? Number(feeRow.rate_pct) : 2.5;

  // Get Omni Runner wallet ID from env
  const omniWalletId = Deno.env.get("ASAAS_OMNI_WALLET_ID") ?? "";

  try {
    switch (action) {
      case "test_connection": {
        const testKey = (body.api_key as string) ?? apiKey;
        const testEnv = (body.environment as string) ?? config?.environment ?? "sandbox";
        const testBase = asaasBase(testEnv);
        const res = await asaasFetch(testBase, testKey, "/finance/getCurrentBalance", "GET");
        if (!res.ok) {
          return jsonOk({ connected: false, error: res.data }, rid, req);
        }
        return jsonOk({ connected: true, balance: res.data }, rid, req);
      }

      case "create_customer": {
        const athleteUserId = body.athlete_user_id as string;
        const name = body.name as string;
        const cpf = body.cpf as string;
        const email = body.email as string;

        if (!athleteUserId || !name || !cpf) {
          return jsonErr(400, "BAD_REQUEST", "athlete_user_id, name, cpf required", rid, undefined, undefined, req);
        }

        // Check if already mapped
        const { data: existing } = await db
          .from("asaas_customer_map")
          .select("asaas_customer_id")
          .eq("group_id", groupId)
          .eq("athlete_user_id", athleteUserId)
          .maybeSingle();

        if (existing) {
          return jsonOk({ asaas_customer_id: existing.asaas_customer_id, already_exists: true }, rid, req);
        }

        // Resolve email from auth if not provided
        let resolvedEmail = email;
        if (!resolvedEmail) {
          const { data: authUser } = await db.auth.admin.getUserById(athleteUserId);
          resolvedEmail = authUser?.user?.email ?? "";
        }

        const custRes = await asaasFetch(base, apiKey, "/customers", "POST", {
          name,
          cpfCnpj: cpf.replace(/\D/g, ""),
          email: resolvedEmail || undefined,
          externalReference: athleteUserId,
          notificationDisabled: false,
        });

        if (!custRes.ok) {
          return jsonErr(502, "ASAAS_ERROR", "Failed to create customer", rid, custRes.data, undefined, req);
        }

        const asaasCustomerId = custRes.data.id as string;

        await db.from("asaas_customer_map").insert({
          group_id: groupId,
          athlete_user_id: athleteUserId,
          asaas_customer_id: asaasCustomerId,
        });

        // Save CPF to coaching_members if not already there
        await db
          .from("coaching_members")
          .update({ cpf: cpf.replace(/\D/g, "") })
          .eq("group_id", groupId)
          .eq("user_id", athleteUserId)
          .is("cpf", null);

        return jsonOk({ asaas_customer_id: asaasCustomerId }, rid, req);
      }

      case "create_subscription": {
        const subscriptionId = body.subscription_id as string;
        const asaasCustomerId = body.asaas_customer_id as string;
        const value = body.value as number;
        const cycle = (body.cycle as string) ?? "MONTHLY";
        const nextDueDate = body.next_due_date as string;
        const description = body.description as string;
        const billingType = (body.billing_type as string) ?? "UNDEFINED";

        if (!subscriptionId || !asaasCustomerId || !value || !nextDueDate) {
          return jsonErr(400, "BAD_REQUEST", "subscription_id, asaas_customer_id, value, next_due_date required", rid, undefined, undefined, req);
        }

        // Check if already mapped
        const { data: existingSub } = await db
          .from("asaas_subscription_map")
          .select("asaas_subscription_id")
          .eq("subscription_id", subscriptionId)
          .maybeSingle();

        if (existingSub) {
          return jsonOk({ asaas_subscription_id: existingSub.asaas_subscription_id, already_exists: true }, rid, req);
        }

        const splitConfig = omniWalletId
          ? [{ walletId: omniWalletId, percentualValue: splitPct }]
          : undefined;

        const subRes = await asaasFetch(base, apiKey, "/subscriptions", "POST", {
          customer: asaasCustomerId,
          billingType,
          value,
          nextDueDate,
          cycle,
          description: description || `Plano assessoria — ${groupId.slice(0, 8)}`,
          externalReference: subscriptionId,
          ...(splitConfig ? { split: splitConfig } : {}),
        });

        if (!subRes.ok) {
          return jsonErr(502, "ASAAS_ERROR", "Failed to create subscription", rid, subRes.data, undefined, req);
        }

        const asaasSubId = subRes.data.id as string;

        await db.from("asaas_subscription_map").insert({
          subscription_id: subscriptionId,
          asaas_subscription_id: asaasSubId,
          asaas_status: subRes.data.status as string ?? "ACTIVE",
        });

        return jsonOk({ asaas_subscription_id: asaasSubId }, rid, req);
      }

      case "cancel_subscription": {
        const subscriptionId = body.subscription_id as string;
        if (!subscriptionId) {
          return jsonErr(400, "BAD_REQUEST", "subscription_id required", rid, undefined, undefined, req);
        }

        const { data: subMap } = await db
          .from("asaas_subscription_map")
          .select("asaas_subscription_id")
          .eq("subscription_id", subscriptionId)
          .maybeSingle();

        if (!subMap) {
          return jsonOk({ cancelled: false, reason: "no_asaas_mapping" }, rid, req);
        }

        const delRes = await asaasFetch(base, apiKey, `/subscriptions/${subMap.asaas_subscription_id}`, "DELETE");

        await db
          .from("asaas_subscription_map")
          .update({ asaas_status: "INACTIVE", last_synced_at: new Date().toISOString() })
          .eq("subscription_id", subscriptionId);

        return jsonOk({ cancelled: true, asaas_response: delRes.data }, rid, req);
      }

      case "setup_webhook": {
        const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
        const webhookUrl = `${supabaseUrl}/functions/v1/asaas-webhook`;
        const webhookToken = crypto.randomUUID();

        const whRes = await asaasFetch(base, apiKey, "/webhooks", "POST", {
          name: "OmniRunner Billing",
          url: webhookUrl,
          email: body.notification_email as string || undefined,
          enabled: true,
          interrupted: false,
          apiVersion: 3,
          authToken: webhookToken,
          sendType: "NON_SEQUENTIALLY",
          events: [
            "PAYMENT_CONFIRMED",
            "PAYMENT_RECEIVED",
            "PAYMENT_OVERDUE",
            "PAYMENT_REFUNDED",
            "PAYMENT_DELETED",
            "SUBSCRIPTION_INACTIVATED",
            "SUBSCRIPTION_DELETED",
          ],
        });

        if (!whRes.ok) {
          return jsonErr(502, "ASAAS_ERROR", "Failed to create webhook", rid, whRes.data, undefined, req);
        }

        await db
          .from("payment_provider_config")
          .update({
            webhook_id: whRes.data.id as string,
            webhook_token: webhookToken,
            is_active: true,
            connected_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq("group_id", groupId)
          .eq("provider", "asaas");

        return jsonOk({ webhook_id: whRes.data.id, webhook_configured: true }, rid, req);
      }

      default:
        return jsonErr(400, "UNKNOWN_ACTION", `Unknown action: ${action}`, rid, undefined, undefined, req);
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return jsonErr(500, "INTERNAL", msg, rid, undefined, undefined, req);
  }
});
