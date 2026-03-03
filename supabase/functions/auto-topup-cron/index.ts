import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * auto-topup-cron — Supabase Edge Function
 *
 * Scheduled via pg_cron (hourly).  Fetches every group with auto
 * top-up enabled and delegates to `auto-topup-check` for each.
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 *
 * POST /auto-topup-cron
 * Headers: Authorization: Bearer <service_role_key>
 * Body: {} (empty or omitted)
 */

const FN = "auto-topup-cron";
const INTER_CALL_DELAY_MS = 200;

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Environment ────────────────────────────────────────────────────
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    // ── 2. Auth (service-role only) ───────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Service role key required", requestId);
    }

    // ── 3. Fetch enabled groups ───────────────────────────────────────────
    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const { data: groups, error: groupsErr } = await db
      .from("billing_auto_topup_settings")
      .select("group_id")
      .eq("enabled", true);

    if (groupsErr) throw groupsErr;

    if (!groups || groups.length === 0) {
      return jsonOk({ processed: 0, triggered: 0, results: [] }, requestId);
    }

    // ── 4. Call auto-topup-check for each group ───────────────────────────
    const checkUrl = `${supabaseUrl}/functions/v1/auto-topup-check`;
    // deno-lint-ignore no-explicit-any
    const results: Record<string, any>[] = [];
    let triggeredCount = 0;

    for (const group of groups) {
      try {
        const res = await fetch(checkUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({ group_id: group.group_id }),
        });

        const data = await res.json();
        if (data.triggered) triggeredCount++;
        results.push({ group_id: group.group_id, ...data });
      } catch (err) {
        results.push({
          group_id: group.group_id,
          ok: false,
          error: (err as Error).message,
        });
      }

      if (groups.length > 1) {
        await new Promise((r) => setTimeout(r, INTER_CALL_DELAY_MS));
      }
    }

    // ── 5. Analytics (fire-and-forget) ────────────────────────────────────
    db.from("product_events")
      .insert({
        user_id: null,
        event_name: "billing_auto_topup_cron_run",
        properties: {
          request_id: requestId,
          groups_checked: groups.length,
          groups_triggered: triggeredCount,
          duration_ms: elapsed(),
        },
      })
      .then(
        () => {},
        () => {},
      );

    return jsonOk(
      {
        processed: groups.length,
        triggered: triggeredCount,
        results,
      },
      requestId,
    );
  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    logError({
      request_id: requestId,
      fn: FN,
      user_id: null,
      error_code: `INTERNAL: ${(err as Error).message}`,
      duration_ms: elapsed(),
    });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId,
        fn: FN,
        user_id: null,
        error_code: errorCode,
        duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId,
        fn: FN,
        user_id: null,
        status,
        duration_ms: elapsed(),
      });
    }
  }
});
