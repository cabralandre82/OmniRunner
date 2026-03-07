import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * billing-reconcile — Supabase Edge Function
 *
 * Reconciles local subscription state with Asaas. Called by cron or admin.
 * Uses service_role (no user auth). For each group with active Asaas config,
 * fetches all mapped subscriptions from Asaas, compares status, and auto-fixes
 * divergences.
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 *
 * POST /billing-reconcile
 * Headers: Authorization: Bearer <service_role_key>
 */

const ASAAS_SANDBOX = "https://api-sandbox.asaas.com/v3";
const ASAAS_PROD = "https://api.asaas.com/v3";
const RATE_LIMIT_MS = 200; // 5 calls per second max

// Asaas subscription status → local coaching_subscriptions.status
// Matches webhook: ACTIVE/INACTIVE/EXPIRED; OVERDUE → late (PAYMENT_OVERDUE)
const STATUS_MAP: Record<string, string> = {
  ACTIVE: "active",
  INACTIVE: "cancelled",
  EXPIRED: "cancelled",
  OVERDUE: "late",
};

function asaasBase(env: string): string {
  return env === "production" ? ASAAS_PROD : ASAAS_SANDBOX;
}

async function asaasGetSubscription(
  baseUrl: string,
  apiKey: string,
  asaasSubscriptionId: string,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const res = await fetch(`${baseUrl}/subscriptions/${asaasSubscriptionId}`, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      access_token: apiKey,
    },
  });
  const data = await res.json();
  return { ok: res.ok, status: res.status, data };
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

serve(async (req: Request) => {
  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    return new Response(JSON.stringify({ status: "ok", version: "2.0.0" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { "Access-Control-Allow-Origin": "*" } });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ ok: false, error: "Server misconfiguration" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (token !== serviceKey) {
    return new Response(
      JSON.stringify({ ok: false, error: "Service role key required" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ ok: false, error: "Method not allowed" }),
      { status: 405, headers: { "Content-Type": "application/json" } },
    );
  }

  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  const divergences: Array<{
    group_id: string;
    subscription_id: string;
    asaas_subscription_id: string;
    local_status: string;
    asaas_status: string;
    auto_fixed: boolean;
  }> = [];
  const errors: string[] = [];
  let groupsChecked = 0;
  let subscriptionsChecked = 0;

  try {
    // 1. Get all groups with payment_provider_config.is_active = true
    const { data: configs, error: configErr } = await db
      .from("payment_provider_config")
      .select("group_id, api_key, environment")
      .eq("provider", "asaas")
      .eq("is_active", true);

    if (configErr) {
      errors.push(`config fetch: ${configErr.message}`);
      return new Response(
        JSON.stringify({
          ok: false,
          groups_checked: 0,
          subscriptions_checked: 0,
          divergences: [],
          errors,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    if (!configs?.length) {
      return new Response(
        JSON.stringify({
          ok: true,
          groups_checked: 0,
          subscriptions_checked: 0,
          divergences: [],
          errors: [],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    for (const config of configs) {
      const groupId = config.group_id as string;
      const apiKey = config.api_key as string;
      const environment = (config.environment as string) ?? "sandbox";
      const base = asaasBase(environment);

      groupsChecked++;

      // 2. Get asaas_subscription_map joined with coaching_subscriptions for this group
      const { data: mappings, error: mapErr } = await db
        .from("asaas_subscription_map")
        .select(`
          subscription_id,
          asaas_subscription_id,
          coaching_subscriptions!inner (
            id,
            status
          )
        `)
        .eq("group_id", groupId);

      if (mapErr) {
        errors.push(`group ${groupId} mappings: ${mapErr.message}`);
        continue;
      }

      if (!mappings?.length) continue;

      for (const row of mappings) {
        const sub = row.coaching_subscriptions as { id: string; status: string } | undefined;
        if (!sub) continue;

        const subscriptionId = row.subscription_id as string;
        const asaasSubscriptionId = row.asaas_subscription_id as string;
        const localStatus = sub.status as string;

        subscriptionsChecked++;

        // Rate limit: max 5 Asaas calls per second
        await sleep(RATE_LIMIT_MS);

        const res = await asaasGetSubscription(base, apiKey, asaasSubscriptionId);

        if (!res.ok) {
          errors.push(
            `group ${groupId} sub ${subscriptionId} asaas ${asaasSubscriptionId}: HTTP ${res.status} ${JSON.stringify(res.data)}`,
          );
          continue;
        }

        const asaasStatus = (res.data.status as string) ?? "";
        const expectedLocalStatus = STATUS_MAP[asaasStatus];

        if (!expectedLocalStatus) {
          errors.push(
            `group ${groupId} sub ${subscriptionId}: unknown Asaas status "${asaasStatus}"`,
          );
          continue;
        }

        if (localStatus !== expectedLocalStatus) {
          // Divergence: auto-fix by updating local status to match Asaas
          const updateData: Record<string, unknown> = {
            status: expectedLocalStatus,
            updated_at: new Date().toISOString(),
          };

          if (expectedLocalStatus === "cancelled") {
            updateData.cancelled_at = new Date().toISOString();
          }

          const { error: updateErr } = await db
            .from("coaching_subscriptions")
            .update(updateData)
            .eq("id", subscriptionId);

          if (updateErr) {
            errors.push(
              `group ${groupId} sub ${subscriptionId} auto-fix failed: ${updateErr.message}`,
            );
            divergences.push({
              group_id: groupId,
              subscription_id: subscriptionId,
              asaas_subscription_id: asaasSubscriptionId,
              local_status: localStatus,
              asaas_status: asaasStatus,
              auto_fixed: false,
            });
          } else {
            divergences.push({
              group_id: groupId,
              subscription_id: subscriptionId,
              asaas_subscription_id: asaasSubscriptionId,
              local_status: localStatus,
              asaas_status: asaasStatus,
              auto_fixed: true,
            });
            // Update asaas_subscription_map.asaas_status and last_synced_at
            await db
              .from("asaas_subscription_map")
              .update({
                asaas_status: asaasStatus,
                last_synced_at: new Date().toISOString(),
              })
              .eq("subscription_id", subscriptionId);
          }
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        groups_checked: groupsChecked,
        subscriptions_checked: subscriptionsChecked,
        divergences,
        errors,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`unexpected: ${msg}`);
    // INTERNAL error — return partial results with error details
    return new Response(
      JSON.stringify({
        ok: false,
        groups_checked: groupsChecked,
        subscriptions_checked: subscriptionsChecked,
        divergences,
        errors,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
