import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain } from "@/test/api-helpers";

const mockFrom = vi.fn(() => queryChain());

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: mockFrom }),
}));
vi.mock("@/lib/logger", () => ({
  logger: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
}));

// L20-03 — mock the tracing facade so we can flip currentTraceId on/off
// per-test. withSpan still passes through to the real fn so we exercise
// the production code path of audit.ts.
const mockCurrentTraceId = vi.fn(() => null as string | null);
const mockCurrentSpanId = vi.fn(() => null as string | null);
vi.mock("@/lib/observability/tracing", () => ({
  withSpan: async (
    _name: string,
    _op: string,
    fn: (setAttr: (k: string, v: unknown) => void) => Promise<unknown>,
  ) => fn(() => {}),
  currentTraceId: () => mockCurrentTraceId(),
  currentSpanId: () => mockCurrentSpanId(),
}));

const { auditLog } = await import("./audit");

describe("auditLog", () => {
  beforeEach(() => vi.clearAllMocks());

  it("inserts a row into portal_audit_log", async () => {
    await auditLog({
      actorId: "user-1",
      groupId: "group-1",
      action: "test.action",
      targetType: "user",
      targetId: "target-1",
      metadata: { foo: "bar" },
    });

    expect(mockFrom).toHaveBeenCalledWith("portal_audit_log");
  });

  it("defaults optional fields to null", async () => {
    const chain = queryChain();
    mockFrom.mockReturnValueOnce(chain);

    await auditLog({ actorId: "user-1", action: "test.minimal" });

    expect(chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        actor_id: "user-1",
        action: "test.minimal",
        group_id: null,
        target_type: null,
        target_id: null,
      }),
    );
  });

  it("never throws even if insert fails", async () => {
    mockFrom.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "db error" } }),
    );

    await expect(
      auditLog({ actorId: "user-1", action: "fail.action" }),
    ).resolves.toBeUndefined();
  });

  it("never throws even if client creation throws", async () => {
    mockFrom.mockImplementationOnce(() => {
      throw new Error("unexpected");
    });

    await expect(
      auditLog({ actorId: "user-1", action: "crash.action" }),
    ).resolves.toBeUndefined();
  });

  // ─── L20-03 — trace_id auto-attachment ───────────────────────────
  describe("L20-03 trace correlation", () => {
    it("auto-attaches trace_id + span_id to metadata when span is active", async () => {
      mockCurrentTraceId.mockReturnValueOnce("abcdef0123456789abcdef0123456789");
      mockCurrentSpanId.mockReturnValueOnce("0123456789abcdef");
      const chain = queryChain();
      mockFrom.mockReturnValueOnce(chain);

      await auditLog({
        actorId: "user-1",
        action: "test.with_trace",
        metadata: { foo: "bar" },
      });

      expect(chain.insert).toHaveBeenCalledWith(
        expect.objectContaining({
          metadata: {
            foo: "bar",
            trace_id: "abcdef0123456789abcdef0123456789",
            span_id: "0123456789abcdef",
          },
        }),
      );
    });

    it("respects caller-provided trace_id (replay/backfill scenario)", async () => {
      mockCurrentTraceId.mockReturnValueOnce("current-trace");
      mockCurrentSpanId.mockReturnValueOnce("current-span");
      const chain = queryChain();
      mockFrom.mockReturnValueOnce(chain);

      await auditLog({
        actorId: "user-1",
        action: "test.replay",
        metadata: { trace_id: "original-trace-from-webhook" },
      });

      const insertedMeta = (chain.insert as unknown as { mock: { calls: unknown[][] } })
        .mock.calls[0][0] as { metadata: Record<string, unknown> };
      expect(insertedMeta.metadata.trace_id).toBe("original-trace-from-webhook");
    });

    it("does NOT add trace_id when no span is active", async () => {
      mockCurrentTraceId.mockReturnValueOnce(null);
      mockCurrentSpanId.mockReturnValueOnce(null);
      const chain = queryChain();
      mockFrom.mockReturnValueOnce(chain);

      await auditLog({
        actorId: "user-1",
        action: "test.no_trace",
        metadata: { foo: "bar" },
      });

      expect(chain.insert).toHaveBeenCalledWith(
        expect.objectContaining({ metadata: { foo: "bar" } }),
      );
    });

    it("handles undefined metadata gracefully (no trace_id when no span)", async () => {
      mockCurrentTraceId.mockReturnValueOnce(null);
      mockCurrentSpanId.mockReturnValueOnce(null);
      const chain = queryChain();
      mockFrom.mockReturnValueOnce(chain);

      await auditLog({ actorId: "user-1", action: "test.minimal_no_trace" });

      expect(chain.insert).toHaveBeenCalledWith(
        expect.objectContaining({ metadata: {} }),
      );
    });
  });
});
