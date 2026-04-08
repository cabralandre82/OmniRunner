import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * release-scheduled-workouts — Supabase Edge Function (cron job)
 *
 * Chamada a cada minuto via pg_cron / pg_net.
 * Libera automaticamente todos os plan_workout_releases cujo
 * scheduled_release_at <= NOW() e release_status = 'scheduled'.
 *
 * Fluxo por lote:
 *   1. Seleciona até MAX_BATCH itens elegíveis (status=scheduled, data passou).
 *   2. Para cada item, chama fn_release_workout_batch() que:
 *      - Atualiza release_status → 'released', released_at = NOW()
 *      - Incrementa content_version se necessário
 *      - Insere registro em workout_change_events (tipo = 'auto_released')
 *      - Invalida sync cursors relacionados ao atleta
 *   3. Retorna contagem de itens processados.
 *
 * Auth: service-role key only (chamada interna via pg_net).
 */

const FN = "release-scheduled-workouts";
const MAX_BATCH = 200;
const MAX_ELAPSED_MS = 50_000;

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET") {
    const path = new URL(req.url).pathname;
    if (path.endsWith("/health")) {
      return new Response(
        JSON.stringify({ status: "ok", fn: FN, version: "1.0.0" }),
        { headers: { "Content-Type": "application/json" } },
      );
    }
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    // Validate caller is using the service role key (cron auth)
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Invalid service key", requestId);
    }

    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    // Guard: abort if already past max elapsed (defensive)
    if (elapsed() > MAX_ELAPSED_MS) {
      status = 503;
      return jsonErr(503, "TIMEOUT", "Cron slot too narrow", requestId);
    }

    // ── Step 1: Find eligible workouts ────────────────────────────────────
    const now = new Date().toISOString();

    const { data: eligible, error: selectErr } = await db
      .from("plan_workout_releases")
      .select("id, athlete_user_id, training_plan_week_id")
      .eq("release_status", "scheduled")
      .lte("scheduled_release_at", now)
      .limit(MAX_BATCH);

    if (selectErr) {
      const classified = classifyError(selectErr);
      status = 500;
      errorCode = classified.code;
      return jsonErr(
        500,
        "DB_SELECT_ERROR",
        selectErr.message,
        requestId,
      );
    }

    if (!eligible || eligible.length === 0) {
      logRequest({
        fn: FN,
        method: req.method,
        status,
        elapsed: elapsed(),
        requestId,
        meta: { released: 0 },
      });
      return jsonOk({ released: 0 }, requestId);
    }

    // ── Step 2: Delegate to the canonical RPC ────────────────────────────
    // fn_process_scheduled_releases() handles all state transitions, audit
    // log entries, sync cursor invalidation, and version bumps atomically.
    const { data: rpcResult, error: rpcErr } = await db.rpc(
      "fn_process_scheduled_releases",
    );

    if (rpcErr) {
      const classified = classifyError(rpcErr);
      status = 500;
      errorCode = classified.code;
      return jsonErr(500, "RPC_ERROR", rpcErr.message, requestId);
    }

    const releasedCount: number =
      typeof rpcResult === "number"
        ? rpcResult
        : (rpcResult?.released_count ?? eligible.length);

    // ── Step 3: Collect unique athlete IDs for push notifications ────────
    const athleteIds = [
      ...new Set(
        (eligible as Array<{ athlete_user_id: string }>).map(
          (r) => r.athlete_user_id,
        ),
      ),
    ];

    // Fire-and-forget: notify athletes. Failures here don't block the cron.
    try {
      await _notifyAthletes(db, athleteIds, releasedCount, requestId);
    } catch (notifyErr) {
      logError({
        fn: FN,
        requestId,
        error: notifyErr,
        context: "notify_athletes",
      });
    }

    logRequest({
      fn: FN,
      method: req.method,
      status,
      elapsed: elapsed(),
      requestId,
      meta: { eligible: eligible.length, released: releasedCount, athletes: athleteIds.length },
    });

    return jsonOk(
      {
        eligible: eligible.length,
        released: releasedCount,
        athletes_notified: athleteIds.length,
      },
      requestId,
    );
  } catch (err) {
    status = 500;
    errorCode = classifyError(err).code;
    logError({ fn: FN, requestId, error: err });
    return jsonErr(
      500,
      errorCode ?? "INTERNAL",
      err instanceof Error ? err.message : String(err),
      requestId,
    );
  }
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function _notifyAthletes(
  // deno-lint-ignore no-explicit-any
  db: any,
  athleteIds: string[],
  workoutCount: number,
  requestId: string,
): Promise<void> {
  if (athleteIds.length === 0) return;

  const plural = workoutCount === 1 ? "treino" : "treinos";
  const body =
    workoutCount === 1
      ? "Um novo treino foi liberado para você."
      : `${workoutCount} ${plural} foram liberados para você.`;

  for (const athleteId of athleteIds) {
    // Insert into a notifications queue that a separate job / realtime listener
    // will pick up and dispatch via FCM/APNS. This keeps this cron decoupled
    // from the push delivery mechanism.
    const { error } = await db.from("notifications").insert({
      user_id: athleteId,
      notification_type: "workout_released",
      title: "Treino disponível 🏃",
      body,
      payload: { trigger: "scheduled_release", request_id: requestId },
      is_read: false,
    });

    if (error) {
      logError({
        fn: "release-scheduled-workouts/_notifyAthletes",
        requestId,
        error,
        context: `athlete_id=${athleteId}`,
      });
    }
  }
}
