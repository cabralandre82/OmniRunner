import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonErr } from "../_shared/http.ts";
import { log } from "../_shared/logger.ts";
import {
  ASAAS_SIGNATURE_HEADER,
  ASAAS_TOKEN_HEADER,
  computeAsaasIdempotencyKey,
  verifyAsaasWebhookAuth,
} from "../_shared/asaas_webhook_auth.ts";

/**
 * Asaas Webhook Receiver (L01-18 hardened).
 *
 * Called by Asaas when payment events occur. Validates `asaas-access-token`
 * (header-only — payload-based `accessToken` removed for defense-in-depth)
 * against the per-group webhook token stored in supabase_vault, and OPTIONALLY
 * verifies an `asaas-signature` HMAC-SHA256 of the raw body when Asaas
 * starts signing payloads.
 *
 * Pipeline:
 *   1. Read raw body once (for both JSON parse AND HMAC / sha256 hashing).
 *   2. Identify group via subscription mapping (need group BEFORE auth to
 *      load the correct vault token — this is OK because the auth check is
 *      constant-time and a bad token leaks "is this a known sub?" bit at
 *      most, which Asaas itself reveals via 200 vs 4xx anyway).
 *   3. Verify auth (verifyAsaasWebhookAuth helper — constant-time, fail-closed).
 *   4. Compute deterministic idempotency key (sha256 fallback — no slice
 *      collisions).
 *   5. INSERT into payment_webhook_events (UNIQUE asaas_event_id catches
 *      replays; reprocess if previously stored but not yet processed).
 *   6. Map status → coaching_subscriptions update with priority guard
 *      (avoid late-arriving overdue overwriting a newer confirmation).
 *   7. Emit maintenance fee revenue / dunning notification side-effects.
 *   8. Mark event as processed.
 *
 * On unhandled exception, persist to billing_webhook_dead_letters for
 * manual triage. The DLQ table itself is now created by migration
 * 20260417290000_billing_webhook_dead_letters.sql.
 *
 * No CORS — server-to-server only.
 */

const GRACE_PERIOD_DAYS = 3;

const STATUS_MAP: Record<string, string> = {
  PAYMENT_CONFIRMED: "active",
  PAYMENT_RECEIVED: "active",
  PAYMENT_OVERDUE: "grace",
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

/**
 * Derive the canonical period_month (first day of the month) for an Asaas
 * payment.
 *
 * Asaas sends `payment.dueDate` in ISO format ("YYYY-MM-DD"). The new-model
 * `athlete_subscription_invoices.period_month` is by CHECK constraint always
 * the first day of the month, so we truncate. When the field is missing or
 * unparseable we fall back to the first day of the current month (UTC) so
 * the bridge can still attempt a match by (subscription_id, period_month).
 *
 * Returns ISO "YYYY-MM-01".
 */
export function derivePeriodMonth(dueDate: string | undefined | null): string {
  if (typeof dueDate === "string" && /^\d{4}-\d{2}-\d{2}/.test(dueDate)) {
    return dueDate.slice(0, 8) + "01";
  }
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, "0");
  return `${y}-${m}-01`;
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

  // ── Variables visible to outer try/catch (DLQ insert) ──────────────────
  // L01-18 bug fix: previously declared inside inner try, causing
  // ReferenceError in the catch-all DLQ insert.
  const requestId = crypto.randomUUID();
  let rawBody = "";
  let payload: Record<string, unknown> = {};
  let event = "unknown";

  try {
    rawBody = await req.text();
    if (rawBody.length === 0) {
      return new Response(JSON.stringify({ error: "Empty body" }), { status: 400 });
    }
    try {
      payload = JSON.parse(rawBody) as Record<string, unknown>;
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400 });
    }

    event = (payload.event as string) ?? "unknown";
    const paymentObj = payload.payment as Record<string, unknown> | undefined;

    if (!event || event === "unknown") {
      return new Response(JSON.stringify({ error: "Missing event" }), { status: 400 });
    }

    const db = getDb();

    // Extract subscription ID from payment.subscription or payment.externalReference
    const asaasSubId = paymentObj?.subscription as string | undefined;
    const asaasPaymentId = paymentObj?.id as string | undefined;
    const externalRef = paymentObj?.externalReference as string | undefined;

    // ── Identify group (needed to load the per-group vault token) ────────
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

    if (!groupId) {
      log("warn", "asaas-webhook unknown_subscription", {
        request_id: requestId,
        event,
        asaas_payment_id: asaasPaymentId,
        asaas_subscription_id: asaasSubId,
      });
      return new Response(
        JSON.stringify({ error: "Unknown subscription — cannot authenticate" }),
        { status: 400 },
      );
    }

    // ── Auth: header-only (payload-based accessToken removed in L01-18) ──
    const incomingToken = req.headers.get(ASAAS_TOKEN_HEADER);
    const incomingSignature = req.headers.get(ASAAS_SIGNATURE_HEADER);

    const { data: storedToken, error: tokenErr } = await db.rpc("fn_ppc_get_webhook_token", {
      p_group_id: groupId,
      p_request_id: `asaas-webhook:${requestId}`,
    });

    if (tokenErr) {
      log("error", "asaas-webhook vault_error", {
        request_id: requestId,
        group_id: groupId,
        message: tokenErr.message,
      });
      return new Response(
        JSON.stringify({ error: `Vault error: ${tokenErr.message}` }),
        { status: 500 },
      );
    }
    if (!storedToken) {
      log("warn", "asaas-webhook missing_vault_token", {
        request_id: requestId,
        group_id: groupId,
      });
      return new Response(
        JSON.stringify({ error: "Webhook token not configured for group" }),
        { status: 401 },
      );
    }

    const authResult = await verifyAsaasWebhookAuth({
      incomingToken,
      incomingSignature,
      storedToken: storedToken as string,
      rawBody,
    });

    if (!authResult.ok) {
      log("warn", "asaas-webhook auth_failed", {
        request_id: requestId,
        group_id: groupId,
        reason: authResult.reason,
        had_signature: Boolean(incomingSignature),
      });
      // 401 across all reasons — never disclose WHICH check failed to caller.
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    log("info", "asaas-webhook auth_ok", {
      request_id: requestId,
      group_id: groupId,
      event,
      signature_verified: authResult.signatureVerified,
    });

    // ── Idempotency key — sha256 fallback (L01-18: no more slice(0,64)) ──
    const eventId = await computeAsaasIdempotencyKey({
      event,
      paymentId: asaasPaymentId ?? null,
      subscriptionId: asaasSubId ?? null,
      rawBody,
    });

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

    // Duplicate event: replay-safe behavior — return ok if already processed.
    if (insertErr?.code === "23505") {
      const { data: existing } = await db
        .from("payment_webhook_events")
        .select("processed")
        .eq("asaas_event_id", eventId)
        .maybeSingle();

      if (existing?.processed) {
        log("info", "asaas-webhook duplicate_replayed", {
          request_id: requestId,
          event_id: eventId,
        });
        return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200 });
      }
      // fall through to reprocess
    } else if (insertErr) {
      log("error", "asaas-webhook db_insert_failed", {
        request_id: requestId,
        event_id: eventId,
        message: insertErr.message,
      });
      return new Response(
        JSON.stringify({ error: `DB insert failed: ${insertErr.message}` }),
        { status: 500 },
      );
    }

    // ── Process payment event → coaching_subscriptions update ────────────
    // STATUS_PRIORITY prevents a late-arriving webhook from overwriting a
    // newer state (e.g. don't downgrade "active" to "grace" if a confirmation
    // arrived first).
    const STATUS_PRIORITY: Record<string, number> = {
      cancelled: 0,
      paused: 1,
      grace: 2,
      late: 3,
      active: 4,
    };

    const newStatus = STATUS_MAP[event];
    const errors: string[] = [];

    if (newStatus && subscriptionId) {
      const { data: currentSub } = await db
        .from("coaching_subscriptions")
        .select("status, updated_at")
        .eq("id", subscriptionId)
        .maybeSingle();

      const currentPriority = STATUS_PRIORITY[currentSub?.status ?? ""] ?? -1;
      const newPriority = STATUS_PRIORITY[newStatus] ?? -1;

      if (currentPriority > newPriority && newStatus !== "cancelled") {
        await db
          .from("payment_webhook_events")
          .update({
            processed: true,
            processed_at: new Date().toISOString(),
            error_message: `skipped: current status "${currentSub?.status}" has higher priority than "${newStatus}"`,
          })
          .eq("asaas_event_id", eventId);
        return new Response(
          JSON.stringify({ ok: true, skipped: true, reason: "stale_event" }),
          { status: 200 },
        );
      }

      const updateData: Record<string, unknown> = {
        status: newStatus,
        updated_at: new Date().toISOString(),
      };

      if (newStatus === "active") {
        updateData.last_payment_at = new Date().toISOString();
        const nextDue = paymentObj?.dueDate as string | undefined;
        if (nextDue) {
          updateData.next_due_date = nextDue;
        }
      }

      if (newStatus === "grace") {
        const graceUntil = new Date(Date.now() + GRACE_PERIOD_DAYS * 86_400_000);
        updateData.grace_until = graceUntil.toISOString();
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

      // ── ADR-0010 F-CON-1 bridge: also close the new-model invoice ─────
      // The webhook historically only updated coaching_subscriptions
      // (legacy). Per ADR-0010 the canonical model is
      // athlete_subscription_invoices. We call a service-role bridge that
      // resolves (group, athlete, period_month) from the legacy sub and
      // marks the corresponding new-model invoice as 'paid' via
      // fn_subscription_mark_invoice_paid. Fail-open: errors are logged
      // and surfaced in `errors[]` but never block the webhook 200 — losing
      // an Asaas event would trigger exponential retry and duplicate
      // processing, which is strictly worse than a transient bridge miss
      // (the cron-health-monitor + audit:billing-models-converged guard
      // will surface persistent divergence). See L09-18.
      if (
        (event === "PAYMENT_CONFIRMED" || event === "PAYMENT_RECEIVED") &&
        subscriptionId
      ) {
        try {
          const periodMonth = derivePeriodMonth(paymentObj?.dueDate as string | undefined);
          const { data: bridgeResult, error: bridgeErr } = await db.rpc(
            "fn_subscription_bridge_mark_paid_from_legacy",
            {
              p_legacy_subscription_id: subscriptionId,
              p_period_month: periodMonth,
              p_external_charge_id: asaasPaymentId ?? null,
            },
          );

          if (bridgeErr) {
            errors.push(`bridge_invoice: ${bridgeErr.message}`);
            log("warn", "asaas-webhook bridge_rpc_error", {
              request_id: requestId,
              subscription_id: subscriptionId,
              event,
              message: bridgeErr.message,
            });
          } else {
            const r = bridgeResult as Record<string, unknown> | null;
            log("info", "asaas-webhook bridge_result", {
              request_id: requestId,
              subscription_id: subscriptionId,
              event,
              bridge_ok: r?.ok ?? null,
              bridge_matched: r?.matched ?? null,
              bridge_was_paid_now: r?.was_paid_now ?? null,
              bridge_reason: r?.reason ?? null,
              invoice_id: r?.invoice_id ?? null,
            });
            if (r?.ok === false) {
              errors.push(`bridge_invoice: ${String(r?.reason ?? "unknown")}`);
            }
          }
        } catch (e) {
          // Never block the webhook on bridge failure (fail-open).
          const msg = e instanceof Error ? e.message : String(e);
          errors.push(`bridge_invoice: ${msg}`);
          log("warn", "asaas-webhook bridge_exception", {
            request_id: requestId,
            subscription_id: subscriptionId,
            event,
            message: msg,
          });
        }
      }

      // Maintenance fee on confirmed payments (idempotent via fee_type+source_ref_id)
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

      // Dunning notification — fire-and-forget, swallow errors
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
          /* fire-and-forget */
        }
      }

      await db
        .from("payment_webhook_events")
        .update({
          processed: !subErr,
          processed_at: new Date().toISOString(),
          error_message: subErr ? subErr.message : null,
        })
        .eq("asaas_event_id", eventId);
    }

    // ── Subscription lifecycle events ────────────────────────────────────
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

    // No-op for unrecognized events — mark processed so we don't reprocess.
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

    return new Response(
      JSON.stringify({ ok: true, errors: errors.length > 0 ? errors : undefined }),
      { status: 200 },
    );
  } catch (error) {
    // ── Dead-letter queue ────────────────────────────────────────────────
    // L01-18: variables now in outer scope so this catch can reference them.
    // The DLQ table is materialized by migration 20260417290000.
    const errMsg = error instanceof Error ? error.message : String(error);
    log("error", "asaas-webhook unhandled", {
      request_id: requestId,
      event,
      message: errMsg,
    });

    try {
      const dlDb = getDb();
      // Strip sensitive headers BEFORE persisting — token would otherwise
      // round-trip into a DB row that may be queried by admin UI.
      const sanitizedHeaders = Object.fromEntries(
        [...req.headers.entries()].filter(
          ([k]) =>
            !["authorization", "cookie", "x-signature", "x-request-id",
              ASAAS_TOKEN_HEADER, ASAAS_SIGNATURE_HEADER].includes(k.toLowerCase()),
        ),
      );
      await dlDb.from("billing_webhook_dead_letters").insert({
        provider: "asaas",
        event_type: event,
        payload,
        headers: sanitizedHeaders,
        error_message: errMsg,
        created_at: new Date().toISOString(),
      });
    } catch (dlErr) {
      log("error", "asaas-webhook dlq_insert_failed", {
        request_id: requestId,
        message: dlErr instanceof Error ? dlErr.message : String(dlErr),
      });
    }
    return jsonErr(
      500,
      "INTERNAL",
      errMsg,
      requestId,
      undefined,
      undefined,
      req,
    );
  }
});
