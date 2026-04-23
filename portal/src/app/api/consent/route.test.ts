import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient } from "@/test/api-helpers";

const supa = makeMockClient(TEST_SESSION);

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => supa,
}));

const { POST, GET } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/consent", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "203.0.113.42",
      "user-agent": "L09-09Test/1.0",
    },
    body: JSON.stringify(body),
  });
}

describe("/api/consent — L04-03 + L09-09 consent_type whitelist", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    supa.auth.getUser.mockResolvedValue({ data: { user: { id: "u-1" } } });
  });

  it("GET returns 401 when not authenticated", async () => {
    supa.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
  });

  it("GET delegates to fn_consent_status", async () => {
    supa.rpc.mockResolvedValueOnce({ data: [{ consent_type: "terms" }], error: null });
    const res = await GET();
    expect(res.status).toBe(200);
    expect(supa.rpc).toHaveBeenCalledWith("fn_consent_status");
  });

  it("POST grant — accepts new club_adhesion type (L09-09)", async () => {
    supa.rpc.mockResolvedValueOnce({
      data: { event_id: "ev-1", consent_type: "club_adhesion" },
      error: null,
    });
    const res = await POST(req({
      action: "grant",
      consent_type: "club_adhesion",
      version: "1.0",
    }));
    expect(res.status).toBe(200);
    expect(supa.rpc).toHaveBeenCalledWith(
      "fn_consent_grant",
      expect.objectContaining({
        p_consent_type: "club_adhesion",
        p_version: "1.0",
        p_source: "portal",
      }),
    );
  });

  it("POST grant — accepts new athlete_contract type (L09-09)", async () => {
    supa.rpc.mockResolvedValueOnce({
      data: { event_id: "ev-2", consent_type: "athlete_contract" },
      error: null,
    });
    const res = await POST(req({
      action: "grant",
      consent_type: "athlete_contract",
      version: "1.0",
    }));
    expect(res.status).toBe(200);
    expect(supa.rpc).toHaveBeenCalledWith(
      "fn_consent_grant",
      expect.objectContaining({ p_consent_type: "athlete_contract" }),
    );
  });

  it("POST grant — still accepts legacy 'terms' type", async () => {
    supa.rpc.mockResolvedValueOnce({ data: { event_id: "ev-3" }, error: null });
    const res = await POST(req({ action: "grant", consent_type: "terms", version: "1.0" }));
    expect(res.status).toBe(200);
  });

  it("POST grant — rejects unknown type with 400", async () => {
    const res = await POST(req({
      action: "grant",
      consent_type: "bogus_type_xyz",
      version: "1.0",
    }));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toMatch(/club_adhesion/);
    expect(body.error).toMatch(/athlete_contract/);
  });

  it("POST revoke — accepts athlete_contract (revogável)", async () => {
    supa.rpc.mockResolvedValueOnce({
      data: { action: "revoked", consent_type: "athlete_contract" },
      error: null,
    });
    const res = await POST(req({ action: "revoke", consent_type: "athlete_contract" }));
    expect(res.status).toBe(200);
    expect(supa.rpc).toHaveBeenCalledWith(
      "fn_consent_revoke",
      expect.objectContaining({ p_consent_type: "athlete_contract" }),
    );
  });

  it("POST grant — propagates RPC error code P0001 as 400", async () => {
    supa.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: "P0001", message: "VERSION_TOO_OLD" },
    });
    const res = await POST(req({
      action: "grant",
      consent_type: "athlete_contract",
      version: "0.5",
    }));
    expect(res.status).toBe(400);
  });

  it("POST grant — version is required", async () => {
    const res = await POST(req({ action: "grant", consent_type: "club_adhesion" }));
    expect(res.status).toBe(400);
  });
});
