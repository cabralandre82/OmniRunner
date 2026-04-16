import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

// ── Mocks ─────────────────────────────────────────────────────────────────────

vi.mock("@/lib/api-handler", () => ({
  withErrorHandler: (fn: Function) => fn,
}));

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

function openaiResponse(data: Record<string, unknown>, status = 200) {
  return Promise.resolve({
    ok: status < 400,
    status,
    statusText: status < 400 ? "OK" : "Bad Request",
    text: () => Promise.resolve(JSON.stringify(data)),
    json: () => Promise.resolve(data),
  });
}

function makeReq(body: unknown) {
  return new NextRequest("http://localhost/api/training-plan/ai/parse-workout", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "test-id" },
    body: JSON.stringify(body),
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("POST /api/training-plan/ai/parse-workout", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("OPENAI_API_KEY", "test-key");
  });

  it("returns 503 when OPENAI_API_KEY is missing", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "30min leve" }));
    const json = await res.json();
    expect(res.status).toBe(503);
    expect(json.error.code).toBe("AI_NOT_CONFIGURED");
  });

  it("returns 422 when text is too short", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "ab" }));
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("returns 422 when text is missing", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq({}));
    const json = await res.json();
    expect(res.status).toBe(422);
  });

  it("returns parsed result with blocks on success", async () => {
    const aiPayload = {
      workout_type: "interval",
      workout_label: "Intervalado 4×1km em 4:30/km",
      description: "4 tiros de 1km",
      coach_notes: "Aquecimento antes",
      estimated_distance_km: 6,
      estimated_duration_minutes: 35,
      blocks: [
        { order_index: 0, block_type: "warmup", duration_seconds: 600, distance_meters: null,
          target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null,
          target_hr_zone: 2, rpe_target: 3, repeat_count: null, notes: null },
        { order_index: 1, block_type: "repeat", duration_seconds: null, distance_meters: null,
          target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null,
          target_hr_zone: null, rpe_target: null, repeat_count: 4, notes: null },
        { order_index: 2, block_type: "interval", duration_seconds: null, distance_meters: 1000,
          target_pace_min_sec_per_km: 255, target_pace_max_sec_per_km: 275,
          target_hr_zone: 4, rpe_target: 8, repeat_count: null, notes: null },
        { order_index: 3, block_type: "recovery", duration_seconds: 120, distance_meters: null,
          target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null,
          target_hr_zone: 2, rpe_target: 3, repeat_count: null, notes: null },
        { order_index: 4, block_type: "cooldown", duration_seconds: 600, distance_meters: null,
          target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null,
          target_hr_zone: 2, rpe_target: 3, repeat_count: null, notes: null },
      ],
    };
    mockFetch.mockReturnValueOnce(openaiResponse({
      choices: [{ message: { content: JSON.stringify(aiPayload) } }],
    }));

    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "4x1km em 4:30 com 2min de descanso" }));
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.workout_type).toBe("interval");
    expect(json.data.workout_label).toBe("Intervalado 4×1km em 4:30/km");
    expect(json.data.blocks).toHaveLength(5);
    expect(json.data.blocks[0].block_type).toBe("warmup");
    expect(json.data.blocks[2].distance_meters).toBe(1000);
    expect(json.data.blocks[2].target_pace_min_sec_per_km).toBe(255);
    expect(json.data.blocks[1].repeat_count).toBe(4);
  });

  it("returns empty blocks array when AI returns none", async () => {
    mockFetch.mockReturnValueOnce(openaiResponse({
      choices: [{
        message: {
          content: JSON.stringify({
            workout_type: "continuous",
            workout_label: "Corrida Leve",
            description: "30min leve",
            coach_notes: null,
            estimated_distance_km: null,
            estimated_duration_minutes: 30,
            blocks: [],
          }),
        },
      }],
    }));

    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "30min leve sem estrutura" }));
    const json = await res.json();

    expect(json.ok).toBe(true);
    expect(json.data.blocks).toEqual([]);
  });

  it("falls back to continuous when AI returns unknown workout_type", async () => {
    mockFetch.mockReturnValueOnce(openaiResponse({
      choices: [{
        message: {
          content: JSON.stringify({
            workout_type: "unknown_type",
            workout_label: "Algo",
            description: null,
            coach_notes: null,
            estimated_distance_km: null,
            estimated_duration_minutes: null,
            blocks: [],
          }),
        },
      }],
    }));

    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "alguma coisa aqui" }));
    const json = await res.json();
    expect(json.data.workout_type).toBe("continuous");
  });

  it("returns 502 when OpenAI call fails", async () => {
    mockFetch.mockReturnValueOnce(openaiResponse({ error: { message: "overloaded" } }, 503));
    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "4x1km em 4:30" }));
    const json = await res.json();
    expect(res.status).toBe(502);
    expect(json.error.code).toBe("AI_API_ERROR");
  });

  it("handles AI response wrapped in markdown code fences", async () => {
    const aiPayload = {
      workout_type: "continuous",
      workout_label: "Corrida 30min",
      description: "30 minutos de corrida leve",
      coach_notes: null,
      estimated_distance_km: 5,
      estimated_duration_minutes: 30,
      blocks: [],
    };
    // Simulate model wrapping JSON in ```json ... ```
    const wrappedContent = "```json\n" + JSON.stringify(aiPayload) + "\n```";
    mockFetch.mockReturnValueOnce(openaiResponse({
      choices: [{ message: { content: wrappedContent }, finish_reason: "stop" }],
    }));

    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "30min leve" }));
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.workout_label).toBe("Corrida 30min");
  });

  it("returns token-limit hint when finish_reason is length", async () => {
    // Simulate truncated response (finish_reason=length breaks the JSON)
    mockFetch.mockReturnValueOnce(openaiResponse({
      choices: [{ message: { content: '{"workout_type":"interval","blocks":[{"order_index":0' }, finish_reason: "length" }],
    }));

    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "treino muito longo com muitos blocos e detalhes" }));
    const json = await res.json();

    expect(res.status).toBe(502);
    expect(json.error.code).toBe("AI_PARSE_ERROR");
    expect(json.error.message).toContain("Resposta cortada");
  });

  it("sanitizes blocks — strips unknown block_type, caps at 30 blocks", async () => {
    const tooManyBlocks = Array.from({ length: 35 }, (_, i) => ({
      order_index: i,
      block_type: i % 2 === 0 ? "interval" : "recovery",
      distance_meters: 500,
      duration_seconds: null,
      target_pace_min_sec_per_km: 270,
      target_pace_max_sec_per_km: 290,
      target_hr_zone: 4,
      rpe_target: 7,
      repeat_count: null,
      notes: null,
    }));

    mockFetch.mockReturnValueOnce(openaiResponse({
      choices: [{
        message: {
          content: JSON.stringify({
            workout_type: "interval",
            workout_label: "Muitos blocos",
            description: null,
            coach_notes: null,
            estimated_distance_km: 17.5,
            estimated_duration_minutes: 90,
            blocks: tooManyBlocks,
          }),
        },
      }],
    }));

    const { POST } = await import("./route");
    const res = await POST(makeReq({ text: "muitos tiros" }));
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.data.blocks.length).toBeLessThanOrEqual(30);
  });
});
