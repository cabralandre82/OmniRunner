import { describe, it, expect, vi, beforeEach } from "vitest";

const mockRpc = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: (...args: unknown[]) => mockRpc(...args),
  }),
}));

const { classifyCronSla, computeCronSlaStats } = await import("./cron-sla");

describe("cron-sla — classifyCronSla (L12-04, mirrors SQL)", () => {
  // The vectors below match the in-migration self-test 1:1. If you
  // change a numeric boundary in either file, change the other in
  // the same PR.

  it("returns 'unknown' when there are no runs in the window", () => {
    expect(classifyCronSla(0, null, null, null, 60, 240, 0, true)).toBe(
      "unknown",
    );
    expect(classifyCronSla(null, null, null, null, 60, 240, 0, true)).toBe(
      "unknown",
    );
  });

  it("returns 'ok' for a fast healthy run", () => {
    expect(classifyCronSla(10, 5, 8, 6, 60, 240, 0, true)).toBe("ok");
  });

  it("returns 'warn' when the last run alone breaches", () => {
    // last (250) > breach (240) → warn
    expect(classifyCronSla(10, 50, 80, 250, 60, 240, 1, true)).toBe("warn");
  });

  it("returns 'warn' when p95 alone breaches", () => {
    // p95 (250) > breach (240) → warn
    expect(classifyCronSla(10, 50, 250, 50, 60, 240, 1, true)).toBe("warn");
  });

  it("returns 'critical' when last run is > 2x breach", () => {
    // last (500) > 2*breach (480) → critical
    expect(classifyCronSla(10, 50, 80, 500, 60, 240, 1, true)).toBe(
      "critical",
    );
  });

  it("returns 'critical' when p95 > 2x breach (even if last is fine)", () => {
    expect(classifyCronSla(10, 50, 500, 50, 60, 240, 1, true)).toBe(
      "critical",
    );
  });

  it("returns 'warn' on sustained drift (avg>target, breach_count>=2)", () => {
    // last (200) and p95 (200) under breach (240) → rules 2/3 don't fire
    // but avg (100) > target (60) and breach_count = 2 → rule 4 fires
    expect(classifyCronSla(10, 100, 200, 200, 60, 240, 2, true)).toBe("warn");
  });

  it("returns 'ok' on a single drift event (insufficient signal)", () => {
    // same drift profile but only 1 breach event ⇒ no warn
    expect(classifyCronSla(10, 100, 200, 200, 60, 240, 1, true)).toBe("ok");
  });

  it("returns 'ok' regardless of metrics when disabled", () => {
    // Catastrophic numbers but enabled=false ⇒ silenced
    expect(
      classifyCronSla(10, 5000, 5000, 5000, 60, 240, 99, false),
    ).toBe("ok");
  });

  it("treats NaN/null thresholds defensively", () => {
    // null breach disables rules 2/3; null target disables rule 4
    expect(classifyCronSla(10, 50, 50, 50, null, null, 0, true)).toBe("ok");
    // NaN treated as null
    expect(classifyCronSla(10, NaN, NaN, NaN, NaN, NaN, NaN, true)).toBe("ok");
  });

  it("ranks last-vs-p95 boundary at exactly breach as 'ok' (>, not >=)", () => {
    // last == breach → not > breach → not warn
    expect(classifyCronSla(10, 50, 80, 240, 60, 240, 0, true)).toBe("ok");
    // last == 2*breach → not > 2*breach → falls to rule 3? No: 240 == breach
    // also fails rule 3 ('>'). last = 240 + 1 = warn.
    expect(classifyCronSla(10, 50, 80, 241, 60, 240, 0, true)).toBe("warn");
  });

  it("severity upgrade: warn region vs critical region per breach multiplier", () => {
    // breach = 100; warn at >100, critical at >200
    expect(classifyCronSla(5, 30, 80, 100, 20, 100, 0, true)).toBe("ok");
    expect(classifyCronSla(5, 30, 80, 101, 20, 100, 0, true)).toBe("warn");
    expect(classifyCronSla(5, 30, 80, 200, 20, 100, 0, true)).toBe("warn");
    expect(classifyCronSla(5, 30, 80, 201, 20, 100, 0, true)).toBe("critical");
  });
});

describe("cron-sla — computeCronSlaStats (L12-04 RPC wrapper)", () => {
  beforeEach(() => {
    mockRpc.mockReset();
  });

  it("returns an empty summary when the RPC returns []", async () => {
    mockRpc.mockResolvedValueOnce({ data: [], error: null });
    const summary = await computeCronSlaStats();
    expect(summary.rows).toEqual([]);
    expect(summary.healthy).toBe(true);
    expect(summary.windowHours).toBe(24);
    expect(summary.countsBySeverity).toEqual({
      ok: 0,
      warn: 0,
      critical: 0,
      unknown: 0,
    });
    expect(mockRpc).toHaveBeenCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 24,
    });
  });

  it("normalises numeric strings (Postgres numeric) into JS numbers", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          name: "clearing-cron",
          schedule: "0 2 * * *",
          expected_interval_seconds: "86400",
          source_thresholds: "configured",
          target_seconds: "60",
          breach_seconds: "240",
          enabled: true,
          run_count: "1",
          failed_count: "0",
          avg_duration_seconds: "30.5",
          p50_duration_seconds: "30",
          p95_duration_seconds: "30.5",
          p99_duration_seconds: "30.5",
          max_duration_seconds: "30.5",
          last_duration_seconds: "30.5",
          last_finished_at: "2026-04-20T02:00:30Z",
          breach_count: "0",
          severity: "ok",
        },
      ],
      error: null,
    });
    const summary = await computeCronSlaStats();
    expect(summary.rows).toHaveLength(1);
    const row = summary.rows[0]!;
    expect(row.name).toBe("clearing-cron");
    expect(row.expectedIntervalSeconds).toBe(86400);
    expect(row.targetSeconds).toBe(60);
    expect(row.breachSeconds).toBe(240);
    expect(row.runCount).toBe(1);
    expect(row.avgDurationSeconds).toBe(30.5);
    expect(row.severity).toBe("ok");
    expect(row.thresholdSource).toBe("configured");
    expect(summary.healthy).toBe(true);
  });

  it("computes counts and unhealthy verdict from row severities", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        bareRow({ name: "j1", severity: "critical" }),
        bareRow({ name: "j2", severity: "warn" }),
        bareRow({ name: "j3", severity: "ok" }),
        bareRow({ name: "j4", severity: "unknown" }),
      ],
      error: null,
    });
    const summary = await computeCronSlaStats();
    expect(summary.countsBySeverity).toEqual({
      critical: 1,
      warn: 1,
      ok: 1,
      unknown: 1,
    });
    expect(summary.healthy).toBe(false);
    expect(summary.rows.map((r) => r.name)).toEqual(["j1", "j2", "j3", "j4"]);
  });

  it("filters by minSeverity (warn drops ok/unknown)", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        bareRow({ name: "j1", severity: "critical" }),
        bareRow({ name: "j2", severity: "warn" }),
        bareRow({ name: "j3", severity: "ok" }),
        bareRow({ name: "j4", severity: "unknown" }),
      ],
      error: null,
    });
    const summary = await computeCronSlaStats({ minSeverity: "warn" });
    expect(summary.rows.map((r) => r.name)).toEqual(["j1", "j2"]);
    expect(summary.countsBySeverity).toEqual({
      critical: 1,
      warn: 1,
      ok: 0,
      unknown: 0,
    });
    expect(summary.healthy).toBe(false);
  });

  it("clamps windowHours into [1, 720] before issuing the RPC", async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });

    await computeCronSlaStats({ windowHours: 0 });
    expect(mockRpc).toHaveBeenLastCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 1,
    });

    await computeCronSlaStats({ windowHours: 1000 });
    expect(mockRpc).toHaveBeenLastCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 720,
    });

    await computeCronSlaStats({ windowHours: 12.7 });
    expect(mockRpc).toHaveBeenLastCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 12,
    });

    await computeCronSlaStats({ windowHours: NaN });
    expect(mockRpc).toHaveBeenLastCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 24,
    });
  });

  it("propagates RPC errors as Error so the endpoint can 500", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "DB exploded" },
    });
    await expect(computeCronSlaStats()).rejects.toThrow(
      /fn_compute_cron_sla_stats failed: DB exploded/,
    );
  });

  it("supports a client injection so tests can avoid the service client", async () => {
    const injectedRpc = vi.fn().mockResolvedValue({
      data: [bareRow({ name: "injected", severity: "ok" })],
      error: null,
    });
    const summary = await computeCronSlaStats({
      client: { rpc: injectedRpc },
      windowHours: 6,
    });
    expect(summary.rows[0]?.name).toBe("injected");
    expect(injectedRpc).toHaveBeenCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 6,
    });
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("normalises garbage rows defensively (drops rows without a name)", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        bareRow({ name: "good", severity: "ok" }),
        bareRow({ name: "", severity: "ok" }),
        bareRow({ name: null, severity: "ok" }),
      ],
      error: null,
    });
    const summary = await computeCronSlaStats();
    expect(summary.rows.map((r) => r.name)).toEqual(["good"]);
  });

  it("falls back to safe defaults when fields are missing/garbage", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          name: "minimal",
          // everything else null / garbage
          schedule: null,
          expected_interval_seconds: null,
          source_thresholds: "weird-string",
          target_seconds: "not a number",
          breach_seconds: null,
          enabled: null,
          run_count: null,
          failed_count: null,
          avg_duration_seconds: null,
          p50_duration_seconds: null,
          p95_duration_seconds: null,
          p99_duration_seconds: null,
          max_duration_seconds: null,
          last_duration_seconds: null,
          last_finished_at: null,
          breach_count: null,
          severity: "weird-string",
        },
      ],
      error: null,
    });
    const summary = await computeCronSlaStats();
    expect(summary.rows).toHaveLength(1);
    const row = summary.rows[0]!;
    expect(row.expectedIntervalSeconds).toBe(86400);
    expect(row.thresholdSource).toBe("derived");
    expect(row.targetSeconds).toBe(0);
    expect(row.breachSeconds).toBe(0);
    expect(row.enabled).toBe(true);
    expect(row.runCount).toBe(0);
    expect(row.severity).toBe("unknown");
  });
});

function bareRow(overrides: Partial<{
  name: string | null;
  schedule: string | null;
  severity: string;
}> = {}) {
  return {
    name: "name" in overrides ? overrides.name ?? null : "job",
    schedule: overrides.schedule ?? "*/5 * * * *",
    expected_interval_seconds: 300,
    source_thresholds: "configured",
    target_seconds: 30,
    breach_seconds: 120,
    enabled: true,
    run_count: 5,
    failed_count: 0,
    avg_duration_seconds: 10,
    p50_duration_seconds: 10,
    p95_duration_seconds: 15,
    p99_duration_seconds: 18,
    max_duration_seconds: 20,
    last_duration_seconds: 11,
    last_finished_at: "2026-04-20T01:00:00Z",
    breach_count: 0,
    severity: overrides.severity ?? "ok",
  };
}
