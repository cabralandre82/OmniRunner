import { describe, it, expect, vi, beforeEach } from "vitest";
import { trackBillingEvent } from "./analytics";

const mockInsert = vi.fn().mockResolvedValue({ error: null });
const mockGetUser = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => ({
    auth: { getUser: mockGetUser },
    from: () => ({ insert: mockInsert }),
  }),
}));

describe("trackBillingEvent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("inserts event when user is authenticated", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u1" } },
    });

    await trackBillingEvent("plan.upgrade", { plan: "pro" });

    expect(mockInsert).toHaveBeenCalledWith({
      user_id: "u1",
      event_name: "plan.upgrade",
      properties: { plan: "pro" },
    });
  });

  it("skips insert when no user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    await trackBillingEvent("test");

    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("never throws even on error", async () => {
    mockGetUser.mockRejectedValue(new Error("network fail"));

    await expect(
      trackBillingEvent("test"),
    ).resolves.toBeUndefined();
  });

  it("passes empty properties by default", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u2" } },
    });

    await trackBillingEvent("page.view");

    expect(mockInsert).toHaveBeenCalledWith(
      expect.objectContaining({ properties: {} }),
    );
  });
});
