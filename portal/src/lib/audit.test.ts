import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain } from "@/test/api-helpers";

const mockFrom = vi.fn(() => queryChain());

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: mockFrom }),
}));
vi.mock("@/lib/logger", () => ({
  logger: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
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
});
