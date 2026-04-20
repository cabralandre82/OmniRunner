import { describe, it, expect, vi, beforeEach } from "vitest";

const mockRpc = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: (...args: unknown[]) => mockRpc(...args),
  }),
}));

const {
  checkWalletLedgerDrift,
  checkAndRecordWalletDrift,
} = await import("./wallet-invariants");

describe("wallet-invariants — checkWalletLedgerDrift (L08-07)", () => {
  beforeEach(() => {
    mockRpc.mockReset();
  });

  it("returns empty rows when DB reports no drift", async () => {
    mockRpc.mockResolvedValueOnce({ data: [], error: null });
    const r = await checkWalletLedgerDrift();
    expect(r.rows).toEqual([]);
    expect(r.scannedMaxUsers).toBe(5000);
    expect(r.recentHours).toBe(24);
    expect(typeof r.checkedAt).toBe("string");
    expect(mockRpc).toHaveBeenCalledWith("fn_check_wallet_ledger_drift", {
      p_max_users: 5000,
      p_recent_hours: 24,
    });
  });

  it("forwards custom maxUsers/recentHours to the RPC", async () => {
    mockRpc.mockResolvedValueOnce({ data: [], error: null });
    await checkWalletLedgerDrift({ maxUsers: 250, recentHours: 6 });
    expect(mockRpc).toHaveBeenCalledWith("fn_check_wallet_ledger_drift", {
      p_max_users: 250,
      p_recent_hours: 6,
    });
  });

  it("normalises bigint-like fields (string → number)", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          user_id: "u-1",
          balance_coins: 100,
          ledger_sum: "75",
          drift: "-25",
          last_reconciled_at_ms: "1745000000000",
          recent_activity: true,
        },
      ],
      error: null,
    });
    const r = await checkWalletLedgerDrift();
    expect(r.rows).toEqual([
      {
        user_id: "u-1",
        balance_coins: 100,
        ledger_sum: 75,
        drift: -25,
        last_reconciled_at_ms: 1_745_000_000_000,
        recent_activity: true,
      },
    ]);
  });

  it("preserves null last_reconciled_at_ms", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          user_id: "u-2",
          balance_coins: 0,
          ledger_sum: 10,
          drift: 10,
          last_reconciled_at_ms: null,
          recent_activity: false,
        },
      ],
      error: null,
    });
    const r = await checkWalletLedgerDrift();
    expect(r.rows[0].last_reconciled_at_ms).toBeNull();
  });

  it("treats data === null as empty array (no rows)", async () => {
    mockRpc.mockResolvedValueOnce({ data: null, error: null });
    const r = await checkWalletLedgerDrift();
    expect(r.rows).toEqual([]);
  });

  it("throws when the RPC returns an error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "lock_timeout exceeded" },
    });
    await expect(checkWalletLedgerDrift()).rejects.toThrow(
      /fn_check_wallet_ledger_drift failed: lock_timeout exceeded/,
    );
  });
});

describe("wallet-invariants — checkAndRecordWalletDrift (L08-07 ↔ L06-03)", () => {
  beforeEach(() => {
    mockRpc.mockReset();
  });

  it("does NOT call fn_record_wallet_drift_event when severity is 'ok'", async () => {
    mockRpc
      .mockResolvedValueOnce({ data: [], error: null }) // fn_check_wallet_ledger_drift
      .mockResolvedValueOnce({ data: "ok", error: null }); // fn_classify_wallet_drift_severity
    const r = await checkAndRecordWalletDrift({
      runId: "11111111-2222-3333-4444-555555555555",
    });
    expect(r.severity).toBe("ok");
    expect(r.eventId).toBeNull();
    expect(r.result.rows).toEqual([]);
    expect(mockRpc).toHaveBeenCalledTimes(2);
    const calls = mockRpc.mock.calls.map((c) => c[0]);
    expect(calls).toEqual([
      "fn_check_wallet_ledger_drift",
      "fn_classify_wallet_drift_severity",
    ]);
  });

  it("persists a wallet_drift_events row when severity is 'warn'", async () => {
    mockRpc
      .mockResolvedValueOnce({
        data: [
          {
            user_id: "u-1",
            balance_coins: 100,
            ledger_sum: 50,
            drift: -50,
            last_reconciled_at_ms: 1_745_000_000_000,
            recent_activity: true,
          },
          {
            user_id: "u-2",
            balance_coins: 0,
            ledger_sum: 5,
            drift: 5,
            last_reconciled_at_ms: null,
            recent_activity: false,
          },
        ],
        error: null,
      })
      .mockResolvedValueOnce({ data: "warn", error: null })
      .mockResolvedValueOnce({ data: "evt-uuid-1", error: null });

    const r = await checkAndRecordWalletDrift({
      runId: "run-1",
      warnThreshold: 10,
      options: { maxUsers: 100, recentHours: 6 },
      notes: { triggered_by: "ops-cli" },
    });
    expect(r.severity).toBe("warn");
    expect(r.eventId).toBe("evt-uuid-1");
    expect(r.result.rows).toHaveLength(2);

    const recordCall = mockRpc.mock.calls.find(
      (c) => c[0] === "fn_record_wallet_drift_event",
    );
    expect(recordCall).toBeTruthy();
    const recordArgs = recordCall![1] as Record<string, unknown>;
    expect(recordArgs.p_run_id).toBe("run-1");
    expect(recordArgs.p_total_wallets).toBe(100);
    expect(recordArgs.p_drifted_count).toBe(2);
    expect(recordArgs.p_severity).toBe("warn");
    const notes = recordArgs.p_notes as Record<string, unknown>;
    expect(notes.source).toBe("platform_admin_realtime");
    expect(notes.warn_threshold).toBe(10);
    expect(notes.recent_hours).toBe(6);
    expect(notes.triggered_by).toBe("ops-cli");
  });

  it("uses default warn threshold (10) when not provided", async () => {
    mockRpc
      .mockResolvedValueOnce({
        data: [{ user_id: "u-x", balance_coins: 1, ledger_sum: 0, drift: -1, last_reconciled_at_ms: null, recent_activity: false }],
        error: null,
      })
      .mockResolvedValueOnce({ data: "warn", error: null })
      .mockResolvedValueOnce({ data: "evt-id", error: null });

    await checkAndRecordWalletDrift({ runId: "run-default" });

    const classifyCall = mockRpc.mock.calls.find(
      (c) => c[0] === "fn_classify_wallet_drift_severity",
    );
    expect(classifyCall![1]).toEqual({
      p_drifted_count: 1,
      p_warn_threshold: 10,
    });
  });

  it("propagates errors from fn_record_wallet_drift_event", async () => {
    mockRpc
      .mockResolvedValueOnce({
        data: [{ user_id: "u-1", balance_coins: 1, ledger_sum: 0, drift: -1, last_reconciled_at_ms: null, recent_activity: true }],
        error: null,
      })
      .mockResolvedValueOnce({ data: "critical", error: null })
      .mockResolvedValueOnce({
        data: null,
        error: { message: "INVALID_RUN_ID: p_run_id is required" },
      });
    await expect(
      checkAndRecordWalletDrift({ runId: "" as unknown as string }),
    ).rejects.toThrow(/fn_record_wallet_drift_event failed: INVALID_RUN_ID/);
  });

  it("propagates errors from fn_classify_wallet_drift_severity", async () => {
    mockRpc
      .mockResolvedValueOnce({ data: [], error: null })
      .mockResolvedValueOnce({
        data: null,
        error: { message: "permission denied for function fn_classify_wallet_drift_severity" },
      });
    await expect(
      checkAndRecordWalletDrift({ runId: "run-x" }),
    ).rejects.toThrow(/fn_classify_wallet_drift_severity failed/);
  });
});
