import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { handleCors } from "../_shared/cors.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";

const FN = "trainingpeaks-sync";
const TP_API = "https://api.trainingpeaks.com/v1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

interface WorkoutBlock {
  order_index: number;
  block_type: string;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_seconds_per_km: number | null;
  target_hr_zone: number | null;
  rpe_target: number | null;
  notes: string | null;
}

function mapBlockTypeToTP(blockType: string): string {
  const mapping: Record<string, string> = {
    warmup: "WarmUp",
    interval: "Interval",
    recovery: "Recovery",
    cooldown: "CoolDown",
    steady: "SteadyState",
  };
  return mapping[blockType] ?? "SteadyState";
}

function buildTPWorkout(templateName: string, scheduledDate: string, blocks: WorkoutBlock[]) {
  return {
    WorkoutDay: scheduledDate,
    Title: templateName,
    WorkoutType: "Run",
    Description: `Treino gerado pelo OmniRunner — ${templateName}`,
    Structure: {
      PrimaryIntensityTarget: { Type: "HeartRate" },
      Steps: blocks.map((b) => ({
        StepOrder: b.order_index,
        IntensityClass: mapBlockTypeToTP(b.block_type),
        Length: b.duration_seconds
          ? { Value: b.duration_seconds, Unit: "Second" }
          : b.distance_meters
            ? { Value: b.distance_meters, Unit: "Meter" }
            : undefined,
        Targets: [
          ...(b.target_hr_zone ? [{ Type: "HeartRateZone", Value: b.target_hr_zone }] : []),
          ...(b.rpe_target ? [{ Type: "RPE", Value: b.rpe_target }] : []),
          ...(b.target_pace_seconds_per_km
            ? [{ Type: "Pace", Value: b.target_pace_seconds_per_km, Unit: "SecondsPerKilometer" }]
            : []),
        ],
        Notes: b.notes ?? undefined,
      })),
    },
  };
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;
  let userId: string | null = null;

  try {
    const url = new URL(req.url);

    if (req.method === "GET" && url.pathname.endsWith("/health")) {
      return jsonOk({ status: "ok", fn: FN }, requestId);
    }

    const flagDb = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: flagRow } = await flagDb
      .from("feature_flags")
      .select("enabled")
      .eq("key", "trainingpeaks_enabled")
      .maybeSingle();
    if (!flagRow?.enabled) {
      status = 403;
      errorCode = "TRAININGPEAKS_DISABLED";
      return jsonErr(403, "TRAININGPEAKS_DISABLED", "TrainingPeaks integration is disabled", requestId);
    }

    const { user } = await requireUser(req);
    userId = user.id;

    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    let body;
    try {
      body = await req.json();
    } catch {
      return jsonErr(400, "INVALID_JSON", "Malformed request body", requestId);
    }
    const action = body.action;
    const db = createClient(SUPABASE_URL, SERVICE_KEY);

    // ── Action: push — Send pending syncs to TrainingPeaks ──────────────
    if (action === "push") {
      const { data: pendingSyncs } = await db
        .from("coaching_tp_sync")
        .select("id, assignment_id, athlete_user_id, group_id")
        .eq("sync_status", "pending")
        .limit(50);

      if (!pendingSyncs?.length) {
        return jsonOk({ pushed: 0, failed: 0 }, requestId);
      }

      const athleteIds = [...new Set(pendingSyncs.map((s) => s.athlete_user_id))];
      const assignmentIds = [...new Set(pendingSyncs.map((s) => s.assignment_id))];

      const { data: deviceLinks } = await db
        .from("coaching_device_links")
        .select("athlete_user_id, access_token, provider_user_id, expires_at")
        .in("athlete_user_id", athleteIds)
        .eq("provider", "trainingpeaks");
      const deviceLinkByAthlete = new Map(
        (deviceLinks ?? []).map((d) => [d.athlete_user_id, d] as const),
      );

      const { data: assignments } = await db
        .from("coaching_workout_assignments")
        .select("id, template_id, scheduled_date")
        .in("id", assignmentIds);
      const assignmentById = new Map(
        (assignments ?? []).map((a) => [a.id, a] as const),
      );

      const templateIds = [...new Set((assignments ?? []).map((a) => a.template_id).filter(Boolean))] as string[];
      const { data: templates } = templateIds.length > 0
        ? await db.from("coaching_workout_templates").select("id, name").in("id", templateIds)
        : { data: null };
      const templateById = new Map(
        (templates ?? []).map((t) => [t.id, t] as const),
      );

      const { data: blocksRows } = templateIds.length > 0
        ? await db
            .from("coaching_workout_blocks")
            .select("template_id, order_index, block_type, duration_seconds, distance_meters, target_pace_seconds_per_km, target_hr_zone, rpe_target, notes")
            .in("template_id", templateIds)
            .order("template_id")
            .order("order_index")
        : { data: null };
      const blocksByTemplateId = new Map<string, WorkoutBlock[]>();
      for (const b of blocksRows ?? []) {
        const existing = blocksByTemplateId.get(b.template_id) ?? [];
        existing.push(b as WorkoutBlock);
        blocksByTemplateId.set(b.template_id, existing);
      }

      let pushed = 0;
      let failed = 0;
      const TIMEOUT_MS = 10_000;
      const CONCURRENCY = 5;

      async function processSingle(sync: typeof pendingSyncs[0]) {
        const deviceLink = deviceLinkByAthlete.get(sync.athlete_user_id);
        const accessToken = deviceLink?.access_token;

        if (!accessToken) {
          await db.from("coaching_tp_sync").update({
            sync_status: "failed",
            error_message: "No access token available",
            updated_at: new Date().toISOString(),
          }).eq("id", sync.id);
          return false;
        }

        const assignment = assignmentById.get(sync.assignment_id);

        if (!assignment) {
          await db.from("coaching_tp_sync").update({
            sync_status: "failed",
            error_message: "Assignment not found",
            updated_at: new Date().toISOString(),
          }).eq("id", sync.id);
          return false;
        }

        const template = assignment.template_id ? templateById.get(assignment.template_id) : null;
        const blocks = assignment.template_id ? (blocksByTemplateId.get(assignment.template_id) ?? []) : [];

        const tpWorkout = buildTPWorkout(
          template?.name ?? "Treino OmniRunner",
          assignment.scheduled_date,
          (blocks ?? []) as WorkoutBlock[],
        );

        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

        try {
          const tpRes = await fetch(`${TP_API}/workouts`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(tpWorkout),
            signal: controller.signal,
          });

          if (tpRes.ok) {
            const tpResult = await tpRes.json();
            await db.from("coaching_tp_sync").update({
              sync_status: "pushed",
              tp_workout_id: tpResult.Id?.toString() ?? null,
              pushed_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            }).eq("id", sync.id);
            return true;
          } else {
            const errText = await tpRes.text();
            await db.from("coaching_tp_sync").update({
              sync_status: "failed",
              error_message: `TP API ${tpRes.status}: ${errText.substring(0, 200)}`,
              updated_at: new Date().toISOString(),
            }).eq("id", sync.id);
            return false;
          }
        } catch (err) {
          await db.from("coaching_tp_sync").update({
            sync_status: "failed",
            error_message: (err as Error).message?.substring(0, 200),
            updated_at: new Date().toISOString(),
          }).eq("id", sync.id);
          return false;
        } finally {
          clearTimeout(timer);
        }
      }

      for (let i = 0; i < pendingSyncs.length; i += CONCURRENCY) {
        const batch = pendingSyncs.slice(i, i + CONCURRENCY);
        const results = await Promise.allSettled(batch.map(processSingle));
        for (const r of results) {
          if (r.status === "fulfilled" && r.value) pushed++;
          else failed++;
        }
      }

      return jsonOk({ pushed, failed }, requestId);
    }

    // ── Action: pull — Import completed workouts from TrainingPeaks ─────
    // KNOWN ISSUE (m18): This pull action has an N+1 pattern — for each athlete
    // link, it fetches workouts, then calls fn_import_execution per workout in a
    // nested loop. This should be batched (e.g. collect all executions and do a
    // single bulk insert or use a batch RPC). However, TrainingPeaks sync is
    // frozen behind the `trainingpeaks_enabled` feature flag and is low-traffic,
    // so this is deferred until the integration is unfrozen.
    if (action === "pull") {
      const groupId = body.group_id;
      if (!groupId) {
        status = 400;
        errorCode = "MISSING_GROUP_ID";
        return jsonErr(400, "MISSING_GROUP_ID", "Missing group_id", requestId);
      }

      const { data: links } = await db
        .from("coaching_device_links")
        .select("athlete_user_id, access_token, provider_user_id")
        .eq("group_id", groupId)
        .eq("provider", "trainingpeaks");

      if (!links?.length) {
        return jsonOk({ imported: 0, message: "No TP links in group" }, requestId);
      }

      let imported = 0;

      for (const link of links) {
        try {
          const since = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
          const until = new Date().toISOString().slice(0, 10);

          const pullCtrl = new AbortController();
          const pullTimer = setTimeout(() => pullCtrl.abort(), 10_000);
          let res: Response;
          try {
            res = await fetch(
              `${TP_API}/workouts/${since}/${until}`,
              { headers: { Authorization: `Bearer ${link.access_token}` }, signal: pullCtrl.signal },
            );
          } finally {
            clearTimeout(pullTimer);
          }

          if (!res.ok) continue;

          const tpWorkouts = await res.json();

          for (const tw of tpWorkouts) {
            if (!tw.CompletedDate || !tw.TotalTimePlanned) continue;

            const { error: importErr } = await db.rpc("fn_import_execution", {
              p_duration_seconds: Math.round(tw.TotalTime ?? tw.TotalTimePlanned ?? 0),
              p_distance_meters: tw.TotalDistance ? Math.round(tw.TotalDistance) : null,
              p_avg_hr: tw.HeartRateAverage ? Math.round(tw.HeartRateAverage) : null,
              p_max_hr: tw.HeartRateMaximum ? Math.round(tw.HeartRateMaximum) : null,
              p_calories: tw.Calories ? Math.round(tw.Calories) : null,
              p_source: "trainingpeaks",
              p_provider_activity_id: `tp_${tw.Id}`,
            });

            if (!importErr) imported++;
          }
        } catch {
          // continue to next athlete
        }
      }

      return jsonOk({ imported }, requestId);
    }

    status = 400;
    errorCode = "UNKNOWN_ACTION";
    return jsonErr(400, "UNKNOWN_ACTION", "Unknown action", requestId);
  } catch (err) {
    if (err instanceof AuthError) {
      status = err.status;
      errorCode = "AUTH";
      return jsonErr(err.status, "AUTH", err.message, requestId);
    }
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status, duration_ms: elapsed() });
    }
  }
});
