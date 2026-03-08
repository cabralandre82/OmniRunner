import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonErr } from "../_shared/http.ts";

/**
 * Asaas Webhook Receiver
 *
 * Called by Asaas when payment events occur. Validates authToken,
 * maps Asaas payment status to coaching_subscriptions status,
 * and logs all events for auditability.
 *
 * No CORS needed — this is called server-to-server by Asaas.
 */

const STATUS_MAP: Record<string, string> = {
  PAYMENT_CONFIRMED: "active",
  PAYMENT_RECEIVED: "active",
  PAYMENT_OVERDUE: "late",
  PAYMENT_REFUNDED: "cancelled",
  PAYMENT_DELETED: "paused",
};

function getDb() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

serve(async (req: Request) => {
  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    return new Response(JSON.stringify({ status: "ok", version: "2.0.0" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  try {
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400 });
  }

  const event = payload.event as string;
  const payment = payload.payment as Record<string, unknown> | undefined;

  if (!event) {
    return new Response(JSON.stringify({ error: "Missing event" }), { status: 400 });
  }

  const db = getDb();

  // Extract subscription ID from payment.subscription or payment.externalReference
  const asaasSubId = payment?.subscription as string | undefined;
  const asaasPaymentId = payment?.id as string | undefined;
  const externalRef = payment?.externalReference as string | undefined;

  // Find which group this webhook belongs to by matching the asaas_subscription_id
  let groupId: string | null = null;
  let subscriptionId: string | null = null;

  if (asaasSubId) {
    const { data: subMap } = await db
      .from("asaas_subscription_map")
      .select("subscription_id")
      .eq("asaas_subscription_id", asaasSubId)
      .maybeSingle();

    if (subMap) {
      subscriptionId = subMap.subscription_id;

      const { data: sub } = await db
        .from("coaching_subscriptions")
        .select("group_id")
        .eq("id", subscriptionId)
        .maybeSingle();

      groupId = sub?.group_id ?? null;
    }
  }

  // Fallback: try externalReference as subscription_id
  if (!subscriptionId && externalRef) {
    const { data: sub } = await db
      .from("coaching_subscriptions")
      .select("id, group_id")
      .eq("id", externalRef)
      .maybeSingle();

    if (sub) {
      subscriptionId = sub.id;
      groupId = sub.group_id;
    }
  }

  // Auth: webhook signature validation — validate authToken against the group's webhook_token
  const incomingToken = req.headers.get("asaas-access-token") ??
    (payload as Record<string, unknown>).accessToken as string | undefined;

  if (!groupId) {
    return new Response(JSON.stringify({ error: "Unknown subscription — cannot authenticate" }), { status: 400 });
  }

  const { data: config } = await db
    .from("payment_provider_config")
    .select("webhook_token")
    .eq("group_id", groupId)
    .eq("provider", "asaas")
    .maybeSingle();

  if (!config?.webhook_token) {
    return new Response(JSON.stringify({ error: "Webhook token not configured for group" }), { status: 401 });
  }

  if (incomingToken !== config.webhook_token) {
    return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401 });
  }

  // Deterministic event ID — never use random UUID, otherwise retries
  // bypass idempotency. Fallback chain: paymentId > subscriptionId > hash of payload
  const eventKey = asaasPaymentId ?? asaasSubId ?? JSON.stringify(payload).slice(0, 64);
  const eventId = `${event}_${eventKey}`;

  const { error: insertErr } = await db
    .from("payment_webhook_events")
    .insert({
      group_id: groupId,
      asaas_event_id: eventId,
      event_type: event,
      asaas_payment_id: asaasPaymentId,
      asaas_subscription_id: asaasSubId,
      payload,
      processed: false,
    });

  // If duplicate event, check if it was fully processed — if not, reprocess
  if (insertErr?.code === "23505") {
    const { data: existing } = await db
      .from("payment_webhook_events")
      .select("processed")
      .eq("asaas_event_id", eventId)
      .maybeSingle();

    if (existing?.processed) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200 });
    }
    // Fall through to reprocess if not yet processed
  } else if (insertErr) {
    return new Response(JSON.stringify({ error: `DB insert failed: ${insertErr.message}` }), { status: 500 });
  }

  // Process payment events → update subscription status
  const newStatus = STATUS_MAP[event];
  const errors: string[] = [];

  if (newStatus && subscriptionId) {
    const updateData: Record<string, unknown> = {
      status: newStatus,
      updated_at: new Date().toISOString(),
    };

    if (newStatus === "active") {
      updateData.last_payment_at = new Date().toISOString();
      const nextDue = payment?.dueDate as string | undefined;
      if (nextDue) {
        updateData.next_due_date = nextDue;
      }
    }

    if (newStatus === "cancelled") {
      updateData.cancelled_at = new Date().toISOString();
    }

    const { error: subErr } = await db
      .from("coaching_subscriptions")
      .update(updateData)
      .eq("id", subscriptionId);

    if (subErr) {
      errors.push(`subscription_update: ${subErr.message}`);
    }

    // Record maintenance fee in platform_revenue on confirmed payments
    if ((event === "PAYMENT_CONFIRMED" || event === "PAYMENT_RECEIVED") && groupId && asaasPaymentId) {
      try {
        const { data: maintCfg } = await db
          .from("platform_fee_config")
          .select("rate_usd, is_active")
          .eq("fee_type", "maintenance")
          .maybeSingle();

        const rateUsd = maintCfg?.is_active && maintCfg?.rate_usd ? Number(maintCfg.rate_usd) : 0;

        if (rateUsd > 0) {
          const { error: revErr } = await db
            .from("platform_revenue")
            .upsert(
              {
                fee_type: "maintenance",
                amount_usd: rateUsd,
                source_ref_id: asaasPaymentId,
                group_id: groupId,
                description: `Manutenção: $${rateUsd}/atleta — pagamento ${asaasPaymentId}`,
              },
              { onConflict: "fee_type,source_ref_id" },
            );

          if (revErr) {
            errors.push(`maintenance_revenue: ${revErr.message}`);
          }
        }
      } catch (e) {
        errors.push(`maintenance_revenue: ${e instanceof Error ? e.message : String(e)}`);
      }
    }

    // Dunning notification: notify athlete of payment failure
    if (event === "PAYMENT_OVERDUE" && subscriptionId) {
      try {
        const { data: sub } = await db
          .from("coaching_subscriptions")
          .select("user_id")
          .eq("id", subscriptionId)
          .maybeSingle();

        if (sub?.user_id) {
          const svcUrl = Deno.env.get("SUPABASE_URL");
          const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
          if (svcUrl && svcKey) {
            fetch(`${svcUrl}/functions/v1/notify-rules`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${svcKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                rule: "payment_overdue",
                context: { user_id: sub.user_id, subscription_id: subscriptionId },
              }),
              signal: AbortSignal.timeout(10_000),
            }).catch(() => {});
          }
        }
      } catch {
        // fire-and-forget dunning notification
      }
    }

    // Mark event as processed
    await db
      .from("payment_webhook_events")
      .update({
        processed: !subErr,
        processed_at: new Date().toISOString(),
        error_message: subErr ? subErr.message : null,
      })
      .eq("asaas_event_id", eventId);
  }

  // Handle subscription lifecycle events
  if (event === "SUBSCRIPTION_INACTIVATED" || event === "SUBSCRIPTION_DELETED") {
    if (asaasSubId) {
      const { error: mapErr } = await db
        .from("asaas_subscription_map")
        .update({ asaas_status: "INACTIVE", last_synced_at: new Date().toISOString() })
        .eq("asaas_subscription_id", asaasSubId);

      if (mapErr) errors.push(`map_update: ${mapErr.message}`);
    }

    if (subscriptionId) {
      const { error: subErr } = await db
        .from("coaching_subscriptions")
        .update({ status: "cancelled", cancelled_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", subscriptionId);

      if (subErr) errors.push(`subscription_cancel: ${subErr.message}`);
    }

    await db
      .from("payment_webhook_events")
      .update({
        processed: errors.length === 0,
        processed_at: new Date().toISOString(),
        error_message: errors.length > 0 ? errors.join("; ") : null,
      })
      .eq("asaas_event_id", eventId);
  }

  // Events that don't match any handler — mark as processed (no-op)
  if (!newStatus && !["SUBSCRIPTION_INACTIVATED", "SUBSCRIPTION_DELETED"].includes(event)) {
    await db
      .from("payment_webhook_events")
      .update({
        processed: true,
        processed_at: new Date().toISOString(),
        error_message: subscriptionId ? null : "no_subscription_match",
      })
      .eq("asaas_event_id", eventId);
  }

  return new Response(JSON.stringify({ ok: true, errors: errors.length > 0 ? errors : undefined }), { status: 200 });
  } catch (error) {
    return jsonErr(500, "INTERNAL", error instanceof Error ? error.message : String(error), undefined, undefined, undefined, req);
  }
});
