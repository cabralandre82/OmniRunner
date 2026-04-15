import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

/**
 * generate-run-comment — Supabase Edge Function
 *
 * Generates a short AI comment (1–2 sentences in Portuguese) comparing
 * a just-finished run to the athlete's recent average.
 *
 * Called by RunSummaryScreen immediately after a run finishes.
 * Silently returns null comment if there is insufficient history (< 3 runs).
 *
 * POST /generate-run-comment
 * Body: {
 *   distance_m:        number,   // this run
 *   duration_s:        number,   // this run
 *   avg_pace_sec_km:   number | null,
 *   avg_bpm:           number | null,
 * }
 * Response: { ok: true, comment: string | null }
 */

const FN = "generate-run-comment";
const MIN_HISTORY_RUNS = 3;
const HISTORY_RUNS_LIMIT = 8;
const SIX_MONTHS_MS = 180 * 86_400_000;

const SYSTEM_PROMPT = `Você é um assistente de treino para corredores.
Com base nos dados da corrida de hoje e na média recente do atleta, escreva 1 ou 2 frases em português brasileiro.
Seja direto, encorajador e factual. Compare o dado mais relevante (pace, distância ou duração).
Nunca dê conselho médico. Nunca invente dados.
Se os dados forem insuficientes para comparar, escreva uma frase genérica de incentivo.
Retorne APENAS o texto, sem JSON, sem prefixos.`;

function fmtPace(secPerKm: number): string {
  const min = Math.floor(secPerKm / 60);
  const sec = Math.round(secPerKm % 60);
  return `${min}'${sec.toString().padStart(2, "0")}"/km`;
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") {
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST");
  }

  const requestId = crypto.randomUUID();

  // ── Auth ─────────────────────────────────────────────────────────────────────
  let user: { id: string };
  // deno-lint-ignore no-explicit-any
  let db: any;

  try {
    const auth = await requireUser(req);
    user = auth.user;
    db = auth.db;
  } catch (e) {
    if (e instanceof AuthError) {
      return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
    }
    return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
  }

  const rl = await checkRateLimit(
    db,
    user.id,
    { fn: FN, maxRequests: 20, windowSeconds: 3600 },
    requestId,
  );
  if (!rl.allowed) return rl.response!;

  // ── Validate body ─────────────────────────────────────────────────────────────
  let body: {
    distance_m?: number;
    duration_s?: number;
    avg_pace_sec_km?: number | null;
    avg_bpm?: number | null;
  };

  try {
    body = await req.json();
  } catch {
    return jsonErr(422, "INVALID_BODY", "Invalid JSON", requestId);
  }

  const distanceM = typeof body.distance_m === "number" ? body.distance_m : null;
  const durationS = typeof body.duration_s === "number" ? body.duration_s : null;
  const paceSecKm = typeof body.avg_pace_sec_km === "number" ? body.avg_pace_sec_km : null;
  const bpm = typeof body.avg_bpm === "number" ? body.avg_bpm : null;

  if (!distanceM || distanceM < 100 || !durationS || durationS < 30) {
    return jsonOk({ comment: null }, requestId);
  }

  // ── Fetch recent sessions history ─────────────────────────────────────────────
  const now = Date.now();
  const cutoff = now - SIX_MONTHS_MS;

  const { data: sessions } = await db
    .from("sessions")
    .select("total_distance_m, moving_ms, avg_pace_sec_km, avg_bpm")
    .eq("user_id", user.id)
    .eq("status", 3)
    .eq("is_verified", true)
    .gte("start_time_ms", cutoff)
    .order("start_time_ms", { ascending: false })
    .limit(HISTORY_RUNS_LIMIT);

  const history = (sessions ?? []) as {
    total_distance_m: number;
    moving_ms: number;
    avg_pace_sec_km: number | null;
    avg_bpm: number | null;
  }[];

  // ── Build LLM context ─────────────────────────────────────────────────────────
  const thisRunKm = (distanceM / 1000).toFixed(2);
  const thisRunMin = Math.round(durationS / 60);
  const thisRunPace = paceSecKm ? fmtPace(paceSecKm) : null;

  let historyContext = "Histórico insuficiente para comparação.";

  if (history.length >= MIN_HISTORY_RUNS) {
    const avgDistKm = history.reduce((s, r) => s + r.total_distance_m, 0) / history.length / 1000;
    const avgDurMin = history.reduce((s, r) => s + (r.moving_ms ?? 0), 0) / history.length / 60_000;
    const paceSessions = history.filter((r) => r.avg_pace_sec_km && r.avg_pace_sec_km > 0);
    const avgPace = paceSessions.length > 0
      ? paceSessions.reduce((s, r) => s + r.avg_pace_sec_km!, 0) / paceSessions.length
      : null;
    const bpmSessions = history.filter((r) => r.avg_bpm && r.avg_bpm > 0);
    const avgHr = bpmSessions.length > 0
      ? Math.round(bpmSessions.reduce((s, r) => s + r.avg_bpm!, 0) / bpmSessions.length)
      : null;

    historyContext = [
      `Média das últimas ${history.length} corridas:`,
      `  Distância: ${avgDistKm.toFixed(2)}km`,
      `  Duração: ${Math.round(avgDurMin)}min`,
      avgPace ? `  Pace médio: ${fmtPace(avgPace)}` : null,
      avgHr ? `  FC média: ${avgHr}bpm` : null,
    ]
      .filter(Boolean)
      .join("\n");
  }

  const userMessage = [
    "Corrida de hoje:",
    `  Distância: ${thisRunKm}km`,
    `  Duração: ${thisRunMin}min`,
    thisRunPace ? `  Pace: ${thisRunPace}` : null,
    bpm ? `  FC média: ${bpm}bpm` : null,
    "",
    historyContext,
  ]
    .filter((l) => l !== null)
    .join("\n");

  // ── Call OpenAI ───────────────────────────────────────────────────────────────
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openaiKey) {
    // Graceful degradation: no AI key → no comment, but don't error
    return jsonOk({ comment: null }, requestId);
  }

  let comment: string | null = null;

  try {
    const aiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userMessage },
        ],
        max_tokens: 120,
        temperature: 0.4,
      }),
    });

    if (aiRes.ok) {
      const aiJson = await aiRes.json();
      const raw: string = aiJson.choices?.[0]?.message?.content ?? "";
      comment = raw.trim().slice(0, 300) || null;
    }
  } catch {
    // Silently swallow — the run summary must always work
  }

  return jsonOk({ comment }, requestId);
});
