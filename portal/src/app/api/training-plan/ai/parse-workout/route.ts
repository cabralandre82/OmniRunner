import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";
import { validateWorkoutBlocks, type ValidatableBlock } from "@/lib/workout/validate";
import type { BlockType } from "@/lib/workout/expand-repeats";

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
- block_type: um de warmup/steady/interval/recovery/repeat/repeat_end/rest/cooldown
  • warmup = aquecimento  • steady = corrida contínua  • interval = tiro/esforço
  • recovery = recuperação ativa  • rest = descanso parado  • cooldown = volta à calma
  • repeat = ABRE grupo de repetição (o próximo bloco é o primeiro da série)
  • repeat_end = FECHA grupo de repetição (OBRIGATÓRIO após o último bloco da série,
    especialmente quando existe cooldown, rest ou steady depois do grupo — sem ele
    o relógio pode repetir blocos que não deveriam fazer parte do loop)
- distance_meters: inteiro em metros (ou null se controlado por tempo)
- duration_seconds: inteiro em segundos (ou null se controlado por distância)
- target_pace_min_sec_per_km: pace mais rápido em segundos/km (ou null)
- target_pace_max_sec_per_km: pace mais lento em segundos/km (ou null)
- target_hr_zone: zona 1-5 (ou null)
- rpe_target: 1-10 (ou null)
- repeat_count: só para block_type=repeat — número de repetições
- rest_mode: só para rest/recovery — "stand_still" (parado/pausa total),
  "walk" (caminhando ativo) ou "jog" (trote leve, APENAS com block_type=recovery).
  null em qualquer outro block_type. Se a descrição não especificar, deixe null.
- notes: observação do bloco (ou null)

Regras de estrutura para intervalados:
  1. Para cada grupo de repetição: repeat → (interval, recovery, ... ) → repeat_end.
  2. SEMPRE feche o repeat com repeat_end ANTES de qualquer cooldown/rest/steady.
  3. Sempre inclua warmup e cooldown quando fizer sentido.
  4. Se a descrição NÃO contiver repetição, NÃO emita repeat nem repeat_end.

Regras de rest_mode (importante para o atleta saber o que fazer no relógio):
  - "parado", "pausa", "pausa total", "respire", "descanso" → block_type=rest + rest_mode="stand_still"
  - "caminhando", "caminhada", "andando" → block_type=rest + rest_mode="walk"
    (mantém block_type=rest porque o atleta não está correndo)
  - "trote leve", "trote", "jog", "recuperação trotando" → block_type=recovery + rest_mode="jog"
  - "recuperação caminhada" → block_type=recovery + rest_mode="walk"
  - Se o texto diz só "recuperação" ou "descanso" sem especificar modo, deixe rest_mode=null.
  - NUNCA emita block_type=rest com rest_mode="jog" (quem trota usa recovery).

Exemplos:
Input: "30min leve"
Output: {"workout_type":"continuous","workout_label":"Corrida Leve 30min","description":"Corrida de 30 minutos em ritmo leve","coach_notes":"Mantenha conversa fácil","estimated_distance_km":null,"estimated_duration_minutes":30,"blocks":[{"order_index":0,"block_type":"warmup","distance_meters":null,"duration_seconds":300,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":"Aquecimento leve"},{"order_index":1,"block_type":"steady","distance_meters":null,"duration_seconds":1500,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":4,"repeat_count":null,"notes":null},{"order_index":2,"block_type":"cooldown","distance_meters":null,"duration_seconds":300,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":1,"rpe_target":2,"repeat_count":null,"notes":null}]}

Input: "4x1km em 4:30 com 2min de descanso"
Output: {"workout_type":"interval","workout_label":"Intervalado 4×1km em 4:30/km","description":"4 repetições de 1km no pace 4:30/km com 2min de recuperação","coach_notes":"Aquecimento de 10min antes. Foco no pace.","estimated_distance_km":8,"estimated_duration_minutes":40,"blocks":[{"order_index":0,"block_type":"warmup","distance_meters":null,"duration_seconds":600,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":null},{"order_index":1,"block_type":"repeat","distance_meters":null,"duration_seconds":null,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":null,"rpe_target":null,"repeat_count":4,"notes":null},{"order_index":2,"block_type":"interval","distance_meters":1000,"duration_seconds":null,"target_pace_min_sec_per_km":255,"target_pace_max_sec_per_km":275,"target_hr_zone":4,"rpe_target":8,"repeat_count":null,"notes":null},{"order_index":3,"block_type":"recovery","distance_meters":null,"duration_seconds":120,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":null},{"order_index":4,"block_type":"repeat_end","distance_meters":null,"duration_seconds":null,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":null,"rpe_target":null,"repeat_count":null,"notes":null},{"order_index":5,"block_type":"cooldown","distance_meters":null,"duration_seconds":600,"target_pace_min_sec_per_km":null,"target_pace_max_sec_per_km":null,"target_hr_zone":2,"rpe_target":3,"repeat_count":null,"notes":null}]}`;

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
  const validBlockTypes = ["warmup", "interval", "recovery", "cooldown", "steady", "rest", "repeat", "repeat_end"];

  // L05-23 strict mode: reject unrecognized block_type with 422 instead of
  // silently downgrading to "steady". A silent downgrade causes the coach to
  // save a workout that looks right in the preview but is semantically
  // different from what they described.
  const rawBlocks = Array.isArray(result.blocks) ? result.blocks : [];
  const invalidBlockTypeIssues: Array<{ index: number; got: unknown }> = [];
  // L05-28: rest_mode sanitization is best-effort. Unknown values, misplaced
  // modes (e.g. 'walk' on an interval), and the illegal rest+jog combo are
  // silently normalized to null — the AI is not perfect at this yet and we
  // prefer a slightly less informative label over a 422 on the coach.
  const validRestModes = ["stand_still", "walk", "jog"] as const;
  const sanitizeRestMode = (
    blockType: string,
    raw: unknown,
  ): "stand_still" | "walk" | "jog" | null => {
    if (typeof raw !== "string") return null;
    if (!validRestModes.includes(raw as typeof validRestModes[number])) return null;
    if (blockType !== "rest" && blockType !== "recovery") return null;
    if (raw === "jog" && blockType !== "recovery") return null;
    return raw as "stand_still" | "walk" | "jog";
  };
  const blocks = rawBlocks
    .filter((b: unknown) => b && typeof b === "object")
    .map((b: Record<string, unknown>, i: number) => {
      if (!validBlockTypes.includes(b.block_type as string)) {
        invalidBlockTypeIssues.push({ index: i, got: b.block_type });
      }
      const blockType = validBlockTypes.includes(b.block_type as string)
        ? (b.block_type as string)
        : "steady";
      return {
        order_index:                i,
        block_type:                 blockType,
        distance_meters:            typeof b.distance_meters === "number" ? Math.round(b.distance_meters) : null,
        duration_seconds:           typeof b.duration_seconds === "number" ? Math.round(b.duration_seconds) : null,
        target_pace_min_sec_per_km: typeof b.target_pace_min_sec_per_km === "number" ? Math.round(b.target_pace_min_sec_per_km) : null,
        target_pace_max_sec_per_km: typeof b.target_pace_max_sec_per_km === "number" ? Math.round(b.target_pace_max_sec_per_km) : null,
        target_hr_zone:             typeof b.target_hr_zone === "number" ? Math.round(b.target_hr_zone) : null,
        target_hr_min:              null,
        target_hr_max:              null,
        rpe_target:                 typeof b.rpe_target === "number" ? Math.round(b.rpe_target) : null,
        repeat_count:               typeof b.repeat_count === "number" ? Math.round(b.repeat_count) : null,
        rest_mode:                  sanitizeRestMode(blockType, b.rest_mode),
        notes:                      typeof b.notes === "string" ? b.notes.slice(0, 200) : null,
      };
    })
    .slice(0, 30);

  if (invalidBlockTypeIssues.length > 0) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "AI_INVALID_BLOCK_TYPE",
          message:
            `A IA retornou block_type(s) fora do enum aceito (${validBlockTypes.join("|")}). ` +
            "Reformule a descrição com mais clareza (ex: \"strides\" → \"aceleradas de 100m\") e tente novamente.",
          details: invalidBlockTypeIssues,
        },
      },
      { status: 422 }
    );
  }

  // L05-23 phase 2: semantic validation of the full block sequence before
  // we send the workout back to the coach. Catches pace inversion, trigger
  // conflicts, repeat imbalance, and estimate hallucination that slip past
  // the JSON schema.
  const estimatedDistanceKm = typeof result.estimated_distance_km === "number"
    ? result.estimated_distance_km
    : null;
  const estimatedDurationMinutes = typeof result.estimated_duration_minutes === "number"
    ? result.estimated_duration_minutes
    : null;

  const validation = validateWorkoutBlocks(
    blocks.map((b) => ({
      block_type: b.block_type as BlockType,
      duration_seconds: b.duration_seconds,
      distance_meters: b.distance_meters,
      target_pace_min_sec_per_km: b.target_pace_min_sec_per_km,
      target_pace_max_sec_per_km: b.target_pace_max_sec_per_km,
      target_hr_min: b.target_hr_min,
      target_hr_max: b.target_hr_max,
      target_hr_zone: b.target_hr_zone,
      repeat_count: b.repeat_count,
      rest_mode: b.rest_mode,
    })) as ValidatableBlock[],
    {
      estimatedDistanceKm,
      estimatedDurationMinutes,
    },
  );

  if (!validation.ok) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "AI_SEMANTIC_VALIDATION_FAILED",
          message:
            "A IA retornou um treino estruturalmente inválido. " +
            "Revise a descrição ou edite os blocos manualmente.",
          details: {
            errors: validation.errors,
            warnings: validation.warnings,
          },
        },
      },
      { status: 422 },
    );
  }

  return NextResponse.json({
    ok: true,
    data: {
      workout_type:               validTypes.includes(result.workout_type as string) ? result.workout_type : "continuous",
      workout_label:              (result.workout_label as string)?.slice(0, 60) ?? "Treino",
      description:                (result.description as string)?.slice(0, 2000) ?? null,
      coach_notes:                (result.coach_notes as string | null) ?? null,
      estimated_distance_km:      estimatedDistanceKm,
      estimated_duration_minutes: estimatedDurationMinutes,
      warnings:                   validation.warnings.length > 0 ? validation.warnings : undefined,
      blocks,
    },
  });
}, "POST /api/training-plan/ai/parse-workout");
