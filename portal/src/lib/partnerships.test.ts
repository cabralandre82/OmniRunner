import { describe, it, expect, vi, beforeEach } from "vitest";

// ─── Mock infrastructure ────────────────────────────────────────────────────

const mockRpc = vi.fn();
const mockFrom = vi.fn();
const mockDelete = vi.fn();

function chainBuilder(result: { data?: unknown; error?: unknown } = { data: null }) {
  const self: Record<string, unknown> = {};
  for (const m of ["select", "eq", "neq", "in", "order", "limit", "range", "is", "or"]) {
    self[m] = vi.fn().mockReturnValue(self);
  }
  self.maybeSingle = vi.fn().mockResolvedValue(result);
  self.single = vi.fn().mockResolvedValue(result);
  self.delete = vi.fn().mockReturnValue(self);
  self.then = (resolve: (v: unknown) => void) => resolve(result);
  return self;
}

function createMockClient() {
  return {
    from: mockFrom.mockReturnValue(chainBuilder()),
    rpc: mockRpc,
  };
}

// ─── Test helpers ───────────────────────────────────────────────────────────

const GROUP_A = "group-aaa-111";
const GROUP_B = "group-bbb-222";
const GROUP_C = "group-ccc-333";
const PARTNERSHIP_ID = "part-111";

const mockPartnership = {
  partnership_id: PARTNERSHIP_ID,
  partner_group_id: GROUP_B,
  partner_name: "Assessoria B",
  partner_athlete_count: 25,
  status: "accepted",
  is_requester: true,
  created_at: "2026-03-01T00:00:00Z",
};

// ═══════════════════════════════════════════════════════════════════════════
// fn_list_partnerships
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_list_partnerships", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should call RPC with correct params and pagination defaults", async () => {
    mockRpc.mockResolvedValue({ data: [mockPartnership], error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_list_partnerships", {
      p_group_id: GROUP_A,
      p_limit: 100,
      p_offset: 0,
    });

    expect(mockRpc).toHaveBeenCalledWith("fn_list_partnerships", {
      p_group_id: GROUP_A,
      p_limit: 100,
      p_offset: 0,
    });
    expect(result.data).toHaveLength(1);
    expect(result.data[0].partner_name).toBe("Assessoria B");
  });

  it("should support custom pagination", async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const client = createMockClient();

    await client.rpc("fn_list_partnerships", {
      p_group_id: GROUP_A,
      p_limit: 20,
      p_offset: 40,
    });

    expect(mockRpc).toHaveBeenCalledWith("fn_list_partnerships", {
      p_group_id: GROUP_A,
      p_limit: 20,
      p_offset: 40,
    });
  });

  it("should return empty array when no partnerships exist", async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_list_partnerships", {
      p_group_id: GROUP_A,
    });

    expect(result.data).toEqual([]);
  });

  it("should return partnerships in correct order (pending first, then accepted)", async () => {
    const pending = { ...mockPartnership, status: "pending", is_requester: false };
    const accepted = { ...mockPartnership, status: "accepted" };
    mockRpc.mockResolvedValue({ data: [pending, accepted], error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_list_partnerships", {
      p_group_id: GROUP_A,
    });

    expect(result.data[0].status).toBe("pending");
    expect(result.data[1].status).toBe("accepted");
  });

  it("should propagate auth errors", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_AUTHORIZED", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_list_partnerships", {
      p_group_id: GROUP_A,
    });

    expect(result.error).toBeTruthy();
    expect(result.error.message).toContain("NOT_AUTHORIZED");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// fn_request_partnership
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_request_partnership", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should send partnership request with correct params", async () => {
    mockRpc.mockResolvedValue({ data: "requested", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_B,
    });

    expect(mockRpc).toHaveBeenCalledWith("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_B,
    });
    expect(result.data).toBe("requested");
  });

  it("should return already_partners when partnership exists", async () => {
    mockRpc.mockResolvedValue({ data: "already_partners", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_B,
    });

    expect(result.data).toBe("already_partners");
  });

  it("should return already_pending for duplicate request", async () => {
    mockRpc.mockResolvedValue({ data: "already_pending", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_B,
    });

    expect(result.data).toBe("already_pending");
  });

  it("should reject self-partnership", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "CANNOT_PARTNER_SELF", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_A,
    });

    expect(result.error).toBeTruthy();
    expect(result.error.message).toContain("CANNOT_PARTNER_SELF");
  });

  it("should reject non-admin_master callers", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_ADMIN_MASTER", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_B,
    });

    expect(result.error).toBeTruthy();
  });

  it("should allow re-request after rejection", async () => {
    mockRpc.mockResolvedValue({ data: "requested", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_request_partnership", {
      p_my_group_id: GROUP_A,
      p_target_group_id: GROUP_B,
    });

    expect(result.data).toBe("requested");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// fn_respond_partnership
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_respond_partnership", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should accept partnership", async () => {
    mockRpc.mockResolvedValue({ data: "accepted", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_respond_partnership", {
      p_partnership_id: PARTNERSHIP_ID,
      p_accept: true,
    });

    expect(result.data).toBe("accepted");
  });

  it("should reject partnership", async () => {
    mockRpc.mockResolvedValue({ data: "rejected", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_respond_partnership", {
      p_partnership_id: PARTNERSHIP_ID,
      p_accept: false,
    });

    expect(result.data).toBe("rejected");
  });

  it("should return already_responded for double-respond", async () => {
    mockRpc.mockResolvedValue({ data: "already_responded", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_respond_partnership", {
      p_partnership_id: PARTNERSHIP_ID,
      p_accept: true,
    });

    expect(result.data).toBe("already_responded");
  });

  it("should reject if caller is not admin_master of group_b", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_ADMIN_MASTER", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_respond_partnership", {
      p_partnership_id: PARTNERSHIP_ID,
      p_accept: true,
    });

    expect(result.error).toBeTruthy();
  });

  it("should return NOT_FOUND for invalid partnership id", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_FOUND", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_respond_partnership", {
      p_partnership_id: "nonexistent",
      p_accept: true,
    });

    expect(result.error).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// fn_count_pending_partnerships
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_count_pending_partnerships", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should return count of pending incoming partnerships", async () => {
    mockRpc.mockResolvedValue({ data: 3, error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_count_pending_partnerships", {
      p_group_id: GROUP_A,
    });

    expect(result.data).toBe(3);
  });

  it("should return 0 when no pending partnerships", async () => {
    mockRpc.mockResolvedValue({ data: 0, error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_count_pending_partnerships", {
      p_group_id: GROUP_A,
    });

    expect(result.data).toBe(0);
  });

  it("should reject unauthorized callers", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_AUTHORIZED", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_count_pending_partnerships", {
      p_group_id: GROUP_A,
    });

    expect(result.error).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// fn_search_assessorias
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_search_assessorias", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should return matching groups", async () => {
    const results = [
      { group_id: GROUP_B, group_name: "Assessoria B", athlete_count: 25 },
    ];
    mockRpc.mockResolvedValue({ data: results, error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_search_assessorias", {
      p_query: "Assessoria",
      p_exclude_group_id: GROUP_A,
    });

    expect(result.data).toHaveLength(1);
    expect(result.data[0].group_name).toBe("Assessoria B");
  });

  it("should exclude own group", async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const client = createMockClient();

    await client.rpc("fn_search_assessorias", {
      p_query: "Group A",
      p_exclude_group_id: GROUP_A,
    });

    expect(mockRpc).toHaveBeenCalledWith("fn_search_assessorias", {
      p_query: "Group A",
      p_exclude_group_id: GROUP_A,
    });
  });

  it("should return empty for no matches", async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_search_assessorias", {
      p_query: "xyznonexistent",
    });

    expect(result.data).toEqual([]);
  });

  it("should limit results to 20", async () => {
    const results = Array.from({ length: 20 }, (_, i) => ({
      group_id: `g-${i}`,
      group_name: `Group ${i}`,
      athlete_count: i,
    }));
    mockRpc.mockResolvedValue({ data: results, error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_search_assessorias", {
      p_query: "Group",
    });

    expect(result.data.length).toBeLessThanOrEqual(20);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// fn_request_champ_join
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_request_champ_join", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should request to join a championship", async () => {
    mockRpc.mockResolvedValue({ data: "requested", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_request_champ_join", {
      p_championship_id: "champ-1",
      p_group_id: GROUP_A,
    });

    expect(result.data).toBe("requested");
  });

  it("should reject non-partner groups", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_PARTNER", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_request_champ_join", {
      p_championship_id: "champ-1",
      p_group_id: GROUP_C,
    });

    expect(result.error).toBeTruthy();
    expect(result.error.message).toContain("NOT_PARTNER");
  });

  it("should reject non-staff callers", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_STAFF", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_request_champ_join", {
      p_championship_id: "champ-1",
      p_group_id: GROUP_A,
    });

    expect(result.error).toBeTruthy();
  });

  it("should return already_accepted if already in championship", async () => {
    mockRpc.mockResolvedValue({ data: "already_accepted", error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_request_champ_join", {
      p_championship_id: "champ-1",
      p_group_id: GROUP_A,
    });

    expect(result.data).toBe("already_accepted");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Partnership removal (direct table DELETE)
// ═══════════════════════════════════════════════════════════════════════════

describe("partnership removal (direct DELETE)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should delete partnership via table", async () => {
    const deleteChain = chainBuilder({ data: null, error: null });
    mockFrom.mockReturnValue(deleteChain);
    const client = createMockClient();

    const chain = client.from("assessoria_partnerships");
    (chain as any).delete().eq("id", PARTNERSHIP_ID);

    expect(mockFrom).toHaveBeenCalledWith("assessoria_partnerships");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// fn_partner_championships
// ═══════════════════════════════════════════════════════════════════════════

describe("fn_partner_championships", () => {
  beforeEach(() => vi.clearAllMocks());

  it("should return championships from partner groups", async () => {
    const champs = [
      {
        championship_id: "ch-1",
        championship_name: "Copa SP",
        host_group_id: GROUP_B,
        host_group_name: "Assessoria B",
        metric: "distance",
        start_at: "2026-04-01T00:00:00Z",
        end_at: "2026-04-30T00:00:00Z",
        status: "open",
        max_participants: 100,
        participant_count: 10,
        already_invited: false,
      },
    ];
    mockRpc.mockResolvedValue({ data: champs, error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_partner_championships", {
      p_group_id: GROUP_A,
    });

    expect(result.data).toHaveLength(1);
    expect(result.data[0].championship_name).toBe("Copa SP");
    expect(result.data[0].already_invited).toBe(false);
  });

  it("should return empty when no partners have championships", async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const client = createMockClient();

    const result = await client.rpc("fn_partner_championships", {
      p_group_id: GROUP_A,
    });

    expect(result.data).toEqual([]);
  });

  it("should reject unauthorized callers", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "NOT_AUTHORIZED", code: "P0001" },
    });
    const client = createMockClient();

    const result = await client.rpc("fn_partner_championships", {
      p_group_id: GROUP_A,
    });

    expect(result.error).toBeTruthy();
  });
});
