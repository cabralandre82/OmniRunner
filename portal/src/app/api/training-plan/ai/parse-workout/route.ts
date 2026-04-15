import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";

const ParseSchema = z.object({
  text: z.string().min(3).max(1000),
});

const SYSTEM_PROMPT = `Você é um assistente de treinamento esportivo especializado em corrida.
Analise a descrição do treino fornecida e retorne um JSON estruturado.

Retorne APENAS um JSON válido com os seguintes campos:
- workout_type: um de continuous/interval/regenerative/long_run/strength/technique/test/free/race/brick
- workout_label: nome curto e descritivo em português (máximo 60 caracteres)
- description: descrição completa e clara do treino em português
- coach_notes: instruções específicas ou avisos para o atleta (ou null)
- estimated_distance_km: distância total estimada em km (número ou null)
- estimated_duration_minutes: duração estimada em minutos (número ou null)

Regras para workout_type:
- continuous = corrida contínua, corrida leve, fartlek
- interval = tiros, intervalados, repetições com descanso
- regenerative = regenerativo, leve de recuperação
- long_run = longão, corrida longa
- strength = musculação, força
- technique = técnica de corrida, mobilidade
- test = teste de pace, teste de esforço
- free = treino livre sem estrutura definida
- race = prova, competição
- brick = treino combinado (bike+corrida, etc.)

Exemplos:
Input: "30min leve"
Output: {"workout_type":"continuous","workout_label":"Corrida Leve 30min","description":"Corrida de 30 minutos em ritmo leve e confortável","coach_notes":"Mantenha uma conversa fácil durante todo o treino","estimated_distance_km":null,"estimated_duration_minutes":30}

Input: "4x1km em 4:30 com 2min de descanso"
Output: {"workout_type":"interval","workout_label":"Intervalado 4×1km em 4:30/km","description":"4 repetições de 1km cada no pace 4:30/km com 2 minutos de recuperação ativa entre cada tiro","coach_notes":"Aquecimento de 10min antes. Foco no pace, não acelere nos últimos 200m.","estimated_distance_km":4,"estimated_duration_minutes":28}`;

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
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: text },
      ],
      max_tokens: 400,
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
  const content = openaiJson.choices?.[0]?.message?.content;

  if (!content) {
    return NextResponse.json(
      { ok: false, error: { code: "AI_EMPTY_RESPONSE" } },
      { status: 502 }
    );
  }

  let result: Record<string, unknown>;
  try {
    result = JSON.parse(content);
  } catch {
    return NextResponse.json(
      { ok: false, error: { code: "AI_PARSE_ERROR", message: "AI returned invalid JSON" } },
      { status: 502 }
    );
  }

  // Validate and sanitize the AI response
  const validTypes = ["continuous", "interval", "regenerative", "long_run", "strength",
    "technique", "test", "free", "race", "brick"];

  return NextResponse.json({
    ok: true,
    data: {
      workout_type:              validTypes.includes(result.workout_type as string) ? result.workout_type : "continuous",
      workout_label:             (result.workout_label as string)?.slice(0, 60) ?? "Treino",
      description:               (result.description as string)?.slice(0, 2000) ?? null,
      coach_notes:               (result.coach_notes as string | null) ?? null,
      estimated_distance_km:     typeof result.estimated_distance_km === "number" ? result.estimated_distance_km : null,
      estimated_duration_minutes: typeof result.estimated_duration_minutes === "number" ? result.estimated_duration_minutes : null,
    },
  });
}, "POST /api/training-plan/ai/parse-workout");
