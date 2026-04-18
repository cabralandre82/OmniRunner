import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { cookies } from "next/headers";
import { randomUUID } from "node:crypto";
import { withErrorHandler } from "@/lib/api-handler";
import { createServiceClient } from "@/lib/supabase/service";
import { createClient } from "@/lib/supabase/server";
import { ensureCoachHealthAccess } from "@/lib/sensitive-access";

const BodySchema = z.object({
  athlete_id: z.string().uuid(),
});

const FOUR_WEEKS_MS = 28 * 86_400_000;
const THIRTY_DAYS_MS = 30 * 86_400_000;

const STATUS_PT: Record<string, string> = {
  active: "ativo",
  paused: "pausado",
  injured: "lesionado",
  inactive: "inativo",
  trial: "em período de teste",
};

const ALERT_PT: Record<string, string> = {
  athlete_high_risk: "risco alto de churn",
  athlete_medium_risk: "risco médio de churn",
  engagement_drop: "queda de engajamento",
  inactive_7d: "inativo há 7 dias",
  inactive_14d: "inativo há 14 dias",
  inactive_30d: "inativo há 30 dias",
};

const SYSTEM_PROMPT = `Você é um assistente especializado em gestão de atletas para treinadores de corrida.
Com base nos dados abaixo, escreva um briefing objetivo em 2 a 4 frases em português brasileiro.
O briefing serve para que o treinador entenda rapidamente o estado atual do atleta antes de uma conversa ou decisão de carga.

Regras:
- Seja factual. Use os números fornecidos.
- Destaque o sinal mais importante (positivo, atenção ou risco).
- Nunca dê conselhos médicos.
- Nunca invente dados que não foram fornecidos.
- Use linguagem direta, sem jargões.

Retorne APENAS um JSON com dois campos:
{ "briefing": "<parágrafo>", "signal": "positive" | "attention" | "risk" }

"positive" = atleta engajado, boa aderência, sem alertas.
"attention" = algum sinal de queda ou carga elevada, mas não crítico.
"risk" = inatividade prolongada, múltiplos alertas, compliance muito baixo.`;

/**
 * POST /api/ai/athlete-briefing
 *
 * Generates a 2–4 sentence AI briefing paragraph for a CRM athlete profile.
 * Fetches all relevant signals server-side and sends structured data to GPT-4o-mini.
 *
 * Body: { athlete_id: string }
 * Response: { ok: true, data: { briefing: string, signal: "positive"|"attention"|"risk" } }
 */
export const POST = withErrorHandler(async (req: NextRequest) => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { ok: false, error: { code: "AI_NOT_CONFIGURED" } },
      { status: 503 }
    );
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json(
      { ok: false, error: { code: "NO_GROUP" } },
      { status: 401 }
    );
  }

  // Verify coach is authenticated
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json(
      { ok: false, error: { code: "UNAUTHORIZED" } },
      { status: 401 }
    );
  }

  const body = await req.json().catch(() => null);
  const parsed = BodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR" } },
      { status: 422 }
    );
  }

  const { athlete_id } = parsed.data;
  const db = createServiceClient();
  const now = Date.now();
  const fourWeeksAgo = new Date(now - FOUR_WEEKS_MS).toISOString();
  const thirtyDaysAgo = new Date(now - THIRTY_DAYS_MS).toISOString();

  // Verify athlete belongs to this group
  const { data: membership } = await db
    .from("coaching_members")
    .select("user_id, display_name, created_at")
    .eq("group_id", groupId)
    .eq("user_id", athlete_id)
    .in("role", ["athlete", "atleta"])
    .maybeSingle();

  if (!membership) {
    return NextResponse.json(
      { ok: false, error: { code: "ATHLETE_NOT_FOUND" } },
      { status: 404 }
    );
  }

  // L04-04: valida consent coach_data_share + loga acesso em sensitive_data_access_log
  // antes de ler sessions.start_time_ms (GPS/HR estão no mesmo snapshot) via service_role.
  const consentCheck = await ensureCoachHealthAccess({
    db,
    actorId: user.id,
    athleteId: athlete_id,
    resource: "sessions",
    action: "read",
    requestId: randomUUID(),
    ip: req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null,
    userAgent: req.headers.get("user-agent"),
  });
  if (!consentCheck.ok) {
    return NextResponse.json(
      { ok: false, error: { code: consentCheck.code, message: consentCheck.message } },
      { status: 403 },
    );
  }

  // Fetch all signals in parallel
  const [
    statusRes,
    tagsRes,
    alertsRes,
    attendanceRes,
    feedbackRes,
    releasesRes,
    lastSessionRes,
    lastNoteRes,
  ] = await Promise.all([
    db.from("coaching_member_status")
      .select("status")
      .eq("group_id", groupId)
      .eq("user_id", athlete_id)
      .maybeSingle(),

    db.from("coaching_athlete_tags")
      .select("coaching_tags(name)")
      .eq("group_id", groupId)
      .eq("athlete_user_id", athlete_id),

    db.from("coaching_alerts")
      .select("alert_type")
      .eq("group_id", groupId)
      .eq("user_id", athlete_id)
      .eq("resolved", false),

    db.from("coaching_training_attendance")
      .select("id", { count: "exact", head: true })
      .eq("group_id", groupId)
      .eq("athlete_user_id", athlete_id)
      .eq("status", "present")
      .gte("created_at", thirtyDaysAgo),

    db.from("athlete_workout_feedback")
      .select("perceived_effort")
      .eq("athlete_user_id", athlete_id)
      .gte("created_at", fourWeeksAgo)
      .not("perceived_effort", "is", null),

    db.from("plan_workout_releases")
      .select("id, release_status")
      .eq("group_id", groupId)
      .eq("athlete_user_id", athlete_id)
      .gte("created_at", fourWeeksAgo),

    db.from("sessions")
      .select("start_time_ms")
      .eq("user_id", athlete_id)
      .eq("status", 3)
      .order("start_time_ms", { ascending: false })
      .limit(1),

    db.from("coaching_athlete_notes")
      .select("created_at")
      .eq("group_id", groupId)
      .eq("athlete_user_id", athlete_id)
      .order("created_at", { ascending: false })
      .limit(1),
  ]);

  // ── Compute metrics ──────────────────────────────────────────────────────────

  const status = (statusRes.data as { status: string } | null)?.status ?? "unknown";

  const tags = (tagsRes.data ?? [])
    .map((t: any) => {
      const ct = Array.isArray(t.coaching_tags) ? t.coaching_tags[0] : t.coaching_tags;
      return ct?.name ?? "";
    })
    .filter(Boolean);

  const alerts = (alertsRes.data ?? []) as { alert_type: string }[];
  const alertLabels = alerts
    .map((a) => ALERT_PT[a.alert_type] ?? a.alert_type)
    .filter(Boolean);

  const attendanceCount = attendanceRes.count ?? 0;

  const feedbacks = (feedbackRes.data ?? []) as { perceived_effort: number }[];
  const avgRpe = feedbacks.length > 0
    ? Math.round((feedbacks.reduce((s, f) => s + (f.perceived_effort ?? 0), 0) / feedbacks.length) * 10) / 10
    : null;

  const releases = (releasesRes.data ?? []) as { id: string; release_status: string }[];
  const prescribedCount = releases.length;
  const completedCount = releases.filter((r) => r.release_status === "completed").length;
  const compliancePct = prescribedCount > 0
    ? Math.round((completedCount / prescribedCount) * 100)
    : null;

  const lastSession = (lastSessionRes.data ?? [])[0] as { start_time_ms: number } | undefined;
  const daysInactive = lastSession
    ? Math.floor((now - lastSession.start_time_ms) / 86_400_000)
    : null;

  const lastNote = (lastNoteRes.data ?? [])[0] as { created_at: string } | undefined;
  const daysSinceNote = lastNote
    ? Math.floor((now - new Date(lastNote.created_at).getTime()) / 86_400_000)
    : null;

  const memberSince = membership.created_at
    ? Math.floor((now - new Date((membership as any).created_at).getTime()) / (30 * 86_400_000))
    : null;

  // ── Build context for the LLM ────────────────────────────────────────────────

  const athleteContext = [
    `Nome: ${(membership as any).display_name || "Atleta"}`,
    `Status: ${STATUS_PT[status] ?? status}`,
    memberSince !== null ? `Tempo na assessoria: ~${memberSince} meses` : null,
    tags.length > 0 ? `Tags: ${tags.join(", ")}` : null,
    `Presenças em treinos presenciais nos últimos 30 dias: ${attendanceCount}`,
    daysInactive !== null
      ? `Dias sem registrar corrida (GPS): ${daysInactive}`
      : "Nenhuma corrida GPS registrada ainda",
    avgRpe !== null
      ? `RPE médio nas últimas 4 semanas: ${avgRpe}/10 (base: ${feedbacks.length} treinos)`
      : "Sem dados de RPE nas últimas 4 semanas",
    compliancePct !== null
      ? `Aderência ao plano nas últimas 4 semanas: ${compliancePct}% (${completedCount} de ${prescribedCount} treinos prescritos)`
      : "Sem treinos prescritos nas últimas 4 semanas",
    alerts.length > 0
      ? `Alertas ativos: ${alertLabels.join("; ")}`
      : "Sem alertas ativos",
    daysSinceNote !== null
      ? `Última nota do treinador: há ${daysSinceNote} dias`
      : "Nenhuma nota do treinador registrada",
  ]
    .filter(Boolean)
    .join("\n");

  // ── Call OpenAI ──────────────────────────────────────────────────────────────

  const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: athleteContext },
      ],
      max_tokens: 300,
      temperature: 0.2,
      response_format: { type: "json_object" },
    }),
  });

  if (!openaiRes.ok) {
    return NextResponse.json(
      { ok: false, error: { code: "AI_API_ERROR" } },
      { status: 502 }
    );
  }

  const openaiJson = await openaiRes.json();
  const content = openaiJson.choices?.[0]?.message?.content;
  if (!content) {
    return NextResponse.json(
      { ok: false, error: { code: "AI_EMPTY_RESPONSE" } },
      { status: 502 }
    );
  }

  let result: { briefing?: string; signal?: string };
  try {
    result = JSON.parse(content);
  } catch {
    return NextResponse.json(
      { ok: false, error: { code: "AI_PARSE_ERROR" } },
      { status: 502 }
    );
  }

  const validSignals = ["positive", "attention", "risk"];
  return NextResponse.json({
    ok: true,
    data: {
      briefing: (result.briefing ?? "").slice(0, 600),
      signal: validSignals.includes(result.signal ?? "") ? result.signal : "attention",
    },
  });
}, "POST /api/ai/athlete-briefing");
