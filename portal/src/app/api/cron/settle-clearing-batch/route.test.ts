import { describe, it, expect, vi, beforeEach } from "vitest";

const settleClearingChunk = vi.fn();
vi.mock("@/lib/clearing", () => ({ settleClearingChunk }));

vi.mock("@/lib/logger", () => ({
  logger: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
}));

vi.mock("@/lib/metrics", () => ({
  metrics: {
    increment: vi.fn(),
    timing: vi.fn(),
    gauge: vi.fn(),
  },
}));

const ORIGINAL_SECRET = process.env.CRON_SECRET;
const VALID_SECRET = "0123456789abcdefghij";

beforeEach(() => {
  vi.clearAllMocks();
  process.env.CRON_SECRET = VALID_SECRET;
});

afterAll(() => {
  if (ORIGINAL_SECRET === undefined) {
    delete process.env.CRON_SECRET;
  } else {
    process.env.CRON_SECRET = ORIGINAL_SECRET;
  }
});

const { POST } = await import("./route");

function makeReq(opts: {
  body?: unknown;
  bearer?: string | null;
  contentLength?: number;
} = {}): import("next/server").NextRequest {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (opts.bearer !== null) {
    headers.Authorization = `Bearer ${opts.bearer ?? VALID_SECRET}`;
  }
  if (opts.contentLength !== undefined) {
    headers["content-length"] = String(opts.contentLength);
  }
  const body = opts.body === undefined ? "" : JSON.stringify(opts.body);
  return new Request("http://localhost/api/cron/settle-clearing-batch", {
    method: "POST",
    headers,
    body: body || undefined,
  }) as unknown as import("next/server").NextRequest;
}

function chunk(overrides: Partial<{
  processed: number;
  settled: number;
  insufficient: number;
  failed: number;
  remaining: number;
}> = {}) {
  return {
    processed: 0,
    settled: 0,
    insufficient: 0,
    failed: 0,
    remaining: 0,
    ...overrides,
  };
}

describe("POST /api/cron/settle-clearing-batch — L02-10", () => {
  it("503 when CRON_SECRET is unset", async () => {
    delete process.env.CRON_SECRET;
    const res = await POST(makeReq());
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error.code).toBe("SERVICE_UNAVAILABLE");
  });

  it("503 when CRON_SECRET is too short", async () => {
    process.env.CRON_SECRET = "tooshort";
    const res = await POST(makeReq());
    expect(res.status).toBe(503);
  });

  it("401 when Authorization header missing", async () => {
    const res = await POST(makeReq({ bearer: null }));
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("401 when bearer is empty", async () => {
    const res = await POST(makeReq({ bearer: "" }));
    expect(res.status).toBe(401);
  });

  it("401 when bearer mismatches (constant-time compare)", async () => {
    const res = await POST(makeReq({ bearer: "wrong-secret-here-zzzz" }));
    expect(res.status).toBe(401);
  });

  it("401 when bearer length differs (no early-return leak)", async () => {
    const res = await POST(makeReq({ bearer: "x" }));
    expect(res.status).toBe(401);
  });

  it("413 when content-length exceeds 4 KiB cap", async () => {
    const res = await POST(makeReq({ contentLength: 5_000 }));
    expect(res.status).toBe(413);
    const body = await res.json();
    expect(body.error.code).toBe("PAYLOAD_TOO_LARGE");
  });

  it("413 when actual body exceeds 4 KiB cap (defends against forged content-length)", async () => {
    const big = { window_hours: 1, padding: "x".repeat(5_000) };
    const res = await POST(makeReq({ body: big }));
    expect(res.status).toBe(413);
  });

  it("400 on invalid JSON", async () => {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      Authorization: `Bearer ${VALID_SECRET}`,
    };
    const req = new Request("http://localhost/api/cron/settle-clearing-batch", {
      method: "POST",
      headers,
      body: "{not json",
    }) as unknown as import("next/server").NextRequest;
    const res = await POST(req);
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
  });

  it("400 when body has unknown field (strict schema)", async () => {
    const res = await POST(makeReq({ body: { unknown_field: 1 } }));
    expect(res.status).toBe(400);
  });

  it("400 when limit exceeds max (500)", async () => {
    const res = await POST(makeReq({ body: { limit: 999 } }));
    expect(res.status).toBe(400);
  });

  it("400 when window_hours is non-positive", async () => {
    const res = await POST(makeReq({ body: { window_hours: 0 } }));
    expect(res.status).toBe(400);
  });

  it("400 when debtor_group_id is not a UUID", async () => {
    const res = await POST(makeReq({ body: { debtor_group_id: "not-a-uuid" } }));
    expect(res.status).toBe(400);
  });

  it("200 + drained=true when first chunk has no work to do (empty body)", async () => {
    settleClearingChunk.mockResolvedValueOnce(chunk());

    const res = await POST(makeReq());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.chunks_processed).toBe(1);
    expect(body.data.drained).toBe(true);
    expect(body.data.stop_reason).toBe("no_progress");
    expect(body.data.window_hours).toBe(168);
    expect(body.data.limit).toBe(50);
  });

  it("loops until remaining=0 and reports stop_reason=drained", async () => {
    settleClearingChunk
      .mockResolvedValueOnce(chunk({ processed: 50, settled: 50, remaining: 100 }))
      .mockResolvedValueOnce(chunk({ processed: 50, settled: 47, insufficient: 2, failed: 1, remaining: 50 }))
      .mockResolvedValueOnce(chunk({ processed: 50, settled: 50, remaining: 0 }));

    const res = await POST(makeReq({ body: { max_chunks: 5 } }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.chunks_processed).toBe(3);
    expect(body.data.total_settled).toBe(147);
    expect(body.data.total_insufficient).toBe(2);
    expect(body.data.total_failed).toBe(1);
    expect(body.data.remaining).toBe(0);
    expect(body.data.drained).toBe(true);
    expect(body.data.stop_reason).toBe("drained");
  });

  it("stops at max_chunks when backlog still has rows", async () => {
    settleClearingChunk.mockResolvedValue(
      chunk({ processed: 50, settled: 50, remaining: 1000 }),
    );

    const res = await POST(makeReq({ body: { max_chunks: 2 } }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.chunks_processed).toBe(2);
    expect(body.data.remaining).toBe(1000);
    expect(body.data.drained).toBe(false);
    expect(body.data.stop_reason).toBe("max_chunks");
    expect(settleClearingChunk).toHaveBeenCalledTimes(2);
  });

  it("forwards debtor_group_id to settleClearingChunk", async () => {
    settleClearingChunk.mockResolvedValueOnce(chunk());
    const debtor = "11111111-2222-4333-8444-555555555555";

    const res = await POST(makeReq({ body: { debtor_group_id: debtor } }));
    expect(res.status).toBe(200);
    expect(settleClearingChunk).toHaveBeenCalledWith(
      expect.objectContaining({ debtorGroupId: debtor }),
    );
  });

  it("500 on chunk RPC error, returning partial counts in details", async () => {
    settleClearingChunk
      .mockResolvedValueOnce(chunk({ processed: 50, settled: 50, remaining: 50 }))
      .mockRejectedValueOnce(new Error("connection terminated"));

    const res = await POST(makeReq({ body: { max_chunks: 5 } }));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("CHUNK_RPC_ERROR");
    expect(body.error.message).toMatch(/Chunk 2\/5 failed/);
    expect(body.error.details).toMatchObject({
      chunks_processed: 1,
      total_settled: 50,
    });
  });

  it("computes window_end = now (within 5s tolerance)", async () => {
    settleClearingChunk.mockResolvedValueOnce(chunk());

    const before = Date.now();
    await POST(makeReq({ body: { window_hours: 24 } }));
    const after = Date.now();

    const call = settleClearingChunk.mock.calls[0]?.[0] as {
      windowStart: Date;
      windowEnd: Date;
    };
    const endMs = call.windowEnd.getTime();
    expect(endMs).toBeGreaterThanOrEqual(before - 100);
    expect(endMs).toBeLessThanOrEqual(after + 100);

    const expectedDeltaMs = 24 * 60 * 60 * 1000;
    expect(endMs - call.windowStart.getTime()).toBe(expectedDeltaMs);
  });
});
