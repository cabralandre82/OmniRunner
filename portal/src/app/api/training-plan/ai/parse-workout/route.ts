import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";

const ParseSchema = z.object({
  text: z.string().min(3).max(1000),
});

const SYSTEM_PROMPT = `Você é um assistente de treinamento esportivo especializado em corrida.
Analise a descrição do treino e retorne um JSON estruturado para ser enviado a relógios GPS.

Retorne APENAS um JSON válido com os seguintes campos:
- workout_type: um de continuous/interval/regenerative/long_run/strength/technique/test/free/race/brick
- workout_label: nome curto e descritivo em português (máximo 60 caracteres)
- description: descrição completa em português
- coach_notes: instruções ou avisos para o atleta (ou null)
- estimated_distance_km: distância total em km (número ou null)
- estimated_duration_minutes: duração total em minutos (número ou null)
- blocks: array de blocos estruturados para guiar o relógio GPS (pode ser [] se treino livre)

Cada bloco em blocks deve ter:
- order_index: inteiro começando em 0
- block_type: um de warmup/steady/interval/recovery/repeat/rest/cooldown
  • warmup = aquecimento  • steady = corrida contínua  • interval = tiro/esforço
  • recovery = recuperação ativa  • repeat = marcador de repetição (envolve os blocos seguintes)
  • rest = descanso parado  • cooldown = volta à calma
- distance_meters: inteiro em metros (ou null se controlado por tempo)
- duration_seconds: inteiro em segundos (ou null se controlado por distância)
- target_pace_min_sec_per_km: pace mais rápido em segundos/km (ou null)
- target_pace_max_sec_per_km: pace mais lento em segundos/km (ou null)
- target_hr_zone: zona 1-5 (ou null)
- rpe_target: 1-10 (ou null)
- repeat_count: só para block_type=repeat — número de repetições
- notes: observação do bloco (ou null)

Regras de estrutura para intervalados: use repeat→interval→recovery→interval→recovery etc.
Sempre inclua warmup e cooldown quando fizer sentido.

Exemplos:
Input: "30min leve"
Output: {"workout_type":"continuous","workout_label":"Corrida Leve 30min","description":"Corrida de 30 minutos em ritmo leve","coach_notes":"Mantenha conversa fácil","estimated_distance_km":null,"estimated_duration_minutes":30,"blocks":[{"order_index":0,"block_type":"warmup","distance_meters":null,"duration_seconds":300,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":"Aquecimento leve"},{"order_index":1,"block_type":"steady","distance_meters":null,"duration_seconds":1500,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":4,"repeat_count":null,"notes":null},{"order_index":2,"block_type":"cooldown","distance_meters":null,"duration_seconds":300,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":1,"rpe_target":2,"repeat_count":null,"notes":null}]}

Input: "4x1km em 4:30 com 2min de descanso"
Output: {"workout_type":"interval","workout_label":"Intervalado 4×1km em 4:30/km","description":"4 repetições de 1km no pace 4:30/km com 2min de recuperação","coach_notes":"Aquecimento de 10min antes. Foco no pace.","estimated_distance_km":8,"estimated_duration_minutes":40,"blocks":[{"order_index":0,"block_type":"warmup","distance_meters":null,"duration_seconds":600,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":null},{"order_index":1,"block_type":"repeat","distance_meters":null,"duration_seconds":null,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":null,"rpe_target":null,"repeat_count":4,"notes":null},{"order_index":2,"block_type":"interval","distance_meters":1000,"duration_seconds":null,"target_pace_min_sec_per_km":255,"target_pace_max_sec_per_km":275,"target_hr_zone":4,"rpe_target":8,"repeat_count":null,"notes":null},{"order_index":3,"block_type":"recovery","distance_meters":null,"duration_seconds":120,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":null},{"order_index":4,"block_type":"cooldown","distance_meters":null,"duration_seconds":600,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":null}]}`;

/**
 * POST /api/training-plan/ai/parse-workout
 *
 * Parses natural language workout description into structured fields.
 * Requires OPENAI_API_KEY environment variable.
 *
 * Body: { text: string }
 * Response: { workout_type, workout_label, description, coach_notes,
 *             estimated_distance_km, estimated_duration_minutes }
 */
export const POST = withErrorHandler(async (req: NextRequest) => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "AI_NOT_CONFIGURED",
          message: "OPENAI_API_KEY não configurada. Adicione ao arquivo .env.local e ao Vercel.",
        },
      },
      { status: 503 }
    );
  }

  const body = await req.json().catch(() => null);
  const parsed = ParseSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const { text } = parsed.data;

  const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: text },
      ],
      max_tokens: 2000,
      temperature: 0.1,
      response_format: { type: "json_object" },
    }),
  });

  if (!openaiRes.ok) {
    const errBody = await openaiRes.text().catch(() => "");
    return NextResponse.json(
      { ok: false, error: { code: "AI_API_ERROR", message: errBody || openaiRes.statusText } },
      { status: 502 }
    );
  }

  const openaiJson = await openaiRes.json();
  const rawContent: string = openaiJson.choices?.[0]?.message?.content ?? "";
  const finishReason: string = openaiJson.choices?.[0]?.finish_reason ?? "";

  if (!rawContent) {
    return NextResponse.json(
      { ok: false, error: { code: "AI_EMPTY_RESPONSE" } },
      { status: 502 }
    );
  }

  // Strip markdown code fences if the model wrapped the JSON (e.g. ```json ... ```)
  const content = rawContent
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();

  let result: Record<string, unknown>;
  try {
    result = JSON.parse(content);
  } catch {
    // If the response was cut off due to token limit, give a clearer error
    const hint = finishReason === "length"
      ? "Resposta cortada por limite de tokens. Tente uma descrição mais curta."
      : "A IA retornou um formato inesperado. Tente novamente.";
    return NextResponse.json(
      { ok: false, error: { code: "AI_PARSE_ERROR", message: hint } },
      { status: 502 }
    );
  }

  // Validate and sanitize the AI response
  const validTypes = ["continuous", "interval", "regenerative", "long_run", "strength",
    "technique", "test", "free", "race", "brick"];
  const validBlockTypes = ["warmup", "interval", "recovery", "cooldown", "steady", "rest", "repeat"];

  const rawBlocks = Array.isArray(result.blocks) ? result.blocks : [];
  const blocks = rawBlocks
    .filter((b: unknown) => b && typeof b === "object")
    .map((b: Record<string, unknown>, i: number) => ({
      order_index:                i,
      block_type:                 validBlockTypes.includes(b.block_type as string) ? b.block_type : "steady",
      distance_meters:            typeof b.distance_meters === "number" ? Math.round(b.distance_meters) : null,
      duration_seconds:           typeof b.duration_seconds === "number" ? Math.round(b.duration_seconds) : null,
      target_pace_min_sec_per_km: typeof b.target_pace_min_sec_per_km === "number" ? Math.round(b.target_pace_min_sec_per_km) : null,
      target_pace_max_sec_per_km: typeof b.target_pace_max_sec_per_km === "number" ? Math.round(b.target_pace_max_sec_per_km) : null,
      target_hr_zone:             typeof b.target_hr_zone === "number" ? Math.round(b.target_hr_zone) : null,
      target_hr_min:              null,
      target_hr_max:              null,
      rpe_target:                 typeof b.rpe_target === "number" ? Math.round(b.rpe_target) : null,
      repeat_count:               typeof b.repeat_count === "number" ? Math.round(b.repeat_count) : null,
      notes:                      typeof b.notes === "string" ? b.notes.slice(0, 200) : null,
    }))
    .slice(0, 30);

  return NextResponse.json({
    ok: true,
    data: {
      workout_type:               validTypes.includes(result.workout_type as string) ? result.workout_type : "continuous",
      workout_label:              (result.workout_label as string)?.slice(0, 60) ?? "Treino",
      description:                (result.description as string)?.slice(0, 2000) ?? null,
      coach_notes:                (result.coach_notes as string | null) ?? null,
      estimated_distance_km:      typeof result.estimated_distance_km === "number" ? result.estimated_distance_km : null,
      estimated_duration_minutes: typeof result.estimated_duration_minutes === "number" ? result.estimated_duration_minutes : null,
      blocks,
    },
  });
}, "POST /api/training-plan/ai/parse-workout");
