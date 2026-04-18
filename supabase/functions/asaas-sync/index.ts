import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
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

serve(async (req: Request) => {
  const url = new URL(req.url);
  if (url.pathname.endsWith('/health')) {
    return new Response(JSON.stringify({ status: 'ok', version: '2.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
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

  // Get provider config (metadata only — secret via RPC L01-17)
  const { data: config } = await db
    .from("payment_provider_config")
    .select("id, group_id, provider, wallet_id, environment, is_active, webhook_id, connected_at, api_key_secret_id, webhook_token_secret_id")
    .eq("group_id", groupId)
    .eq("provider", "asaas")
    .maybeSingle();

  if (!config && action !== "test_connection") {
    return jsonErr(404, "NO_CONFIG", "Asaas not configured for this group", rid, undefined, undefined, req);
  }

  // Resolve API key via vault RPC (L01-17). test_connection may use a body-supplied
  // key (for "save before connect" flow); other actions require the stored secret.
  let apiKey = "";
  if (config?.api_key_secret_id) {
    const { data: keyData, error: keyErr } = await db.rpc("fn_ppc_get_api_key", {
      p_group_id: groupId,
      p_request_id: rid,
    });
    if (keyErr || !keyData) {
      return jsonErr(500, "VAULT_ERROR", `Failed to decrypt API key: ${keyErr?.message ?? "null"}`, rid, undefined, undefined, req);
    }
    apiKey = keyData as string;
  }
  const base = asaasBase(config?.environment as string ?? "sandbox");

  // Get platform fee config: billing_split (%) + maintenance (fixed USD/athlete)
  const { data: feeRows } = await db
    .from("platform_fee_config")
    .select("fee_type, rate_pct, rate_usd, is_active")
    .in("fee_type", ["billing_split", "maintenance"]);

  const splitRow = feeRows?.find((r: Record<string, unknown>) => r.fee_type === "billing_split");
  const maintRow = feeRows?.find((r: Record<string, unknown>) => r.fee_type === "maintenance");

  const splitPct = splitRow?.is_active && splitRow?.rate_pct ? Number(splitRow.rate_pct) : 2.5;
  const maintenanceUsd = maintRow?.is_active && maintRow?.rate_usd ? Number(maintRow.rate_usd) : 0;

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

        // Atomic upsert — prevents race condition between concurrent requests
        // Try INSERT first; if conflict, return existing record
        const { data: upserted, error: upsertErr } = await db
          .from("asaas_customer_map")
          .select("asaas_customer_id")
          .eq("group_id", groupId)
          .eq("athlete_user_id", athleteUserId)
          .maybeSingle();

        if (upserted) {
          return jsonOk({ asaas_customer_id: upserted.asaas_customer_id, already_exists: true }, rid, req);
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

        // Upsert to handle concurrent requests — if another request already
        // inserted between our SELECT and here, we just keep the existing row
        const { error: insertErr } = await db
          .from("asaas_customer_map")
          .upsert(
            {
              group_id: groupId,
              athlete_user_id: athleteUserId,
              asaas_customer_id: asaasCustomerId,
            },
            { onConflict: "group_id,athlete_user_id", ignoreDuplicates: true },
          );

        if (insertErr) {
          return jsonErr(500, "DB_ERROR", `Failed to persist customer mapping: ${insertErr.message}`, rid, undefined, undefined, req);
        }

        // Save CPF to coaching_members
        const { error: cpfErr } = await db
          .from("coaching_members")
          .update({ cpf: cpf.replace(/\D/g, "") })
          .eq("group_id", groupId)
          .eq("user_id", athleteUserId)
          .is("cpf", null);

        if (cpfErr) {
          console.error(`[asaas-sync] CPF save failed for ${athleteUserId}: ${cpfErr.message}`);
        }

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

        // Idempotent check — return existing if already mapped
        const { data: existingSub } = await db
          .from("asaas_subscription_map")
          .select("asaas_subscription_id")
          .eq("subscription_id", subscriptionId)
          .maybeSingle();

        if (existingSub) {
          return jsonOk({ asaas_subscription_id: existingSub.asaas_subscription_id, already_exists: true }, rid, req);
        }

        const splitEntries: Array<Record<string, unknown>> = [];
        if (omniWalletId) {
          if (splitPct > 0) {
            splitEntries.push({ walletId: omniWalletId, percentualValue: splitPct });
          }
          if (maintenanceUsd > 0) {
            splitEntries.push({ walletId: omniWalletId, fixedValue: maintenanceUsd });
          }
        }
        const splitConfig = splitEntries.length > 0 ? splitEntries : undefined;

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

        // Upsert to handle concurrent requests
        const { error: mapErr } = await db
          .from("asaas_subscription_map")
          .upsert(
            {
              subscription_id: subscriptionId,
              asaas_subscription_id: asaasSubId,
              asaas_status: (subRes.data.status as string) ?? "ACTIVE",
              group_id: groupId,
            },
            { onConflict: "subscription_id", ignoreDuplicates: true },
          );

        if (mapErr) {
          return jsonErr(500, "DB_ERROR", `Failed to persist subscription mapping: ${mapErr.message}`, rid, undefined, undefined, req);
        }

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

        const { error: cancelErr } = await db
          .from("asaas_subscription_map")
          .update({ asaas_status: "INACTIVE", last_synced_at: new Date().toISOString() })
          .eq("subscription_id", subscriptionId);

        if (cancelErr) {
          return jsonErr(500, "DB_ERROR", `Asaas cancelled but DB update failed: ${cancelErr.message}`, rid, undefined, undefined, req);
        }

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

        const { error: whDbErr } = await db.rpc("fn_ppc_save_webhook_token", {
          p_group_id: groupId,
          p_webhook_id: whRes.data.id as string,
          p_token: webhookToken,
          p_request_id: rid,
        });

        if (whDbErr) {
          return jsonErr(500, "DB_ERROR", `Webhook created but vault save failed: ${whDbErr.message}`, rid, undefined, undefined, req);
        }

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
