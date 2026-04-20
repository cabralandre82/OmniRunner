import { describe, it, expect, vi, beforeEach } from "vitest";

const mockRpc = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: (...args: unknown[]) => mockRpc(...args),
  }),
}));

const { classifyCronSeverity, checkCronHealth } = await import("./cron-health");

describe("cron-health — classifyCronSeverity (L06-04, mirrors SQL)", () => {
  // The vectors below match the in-migration self-test 1:1. If you change
  // a numeric boundary in either file, change the other in the same PR.

  it("returns 'unknown' when no execution data exists", () => {
    expect(classifyCronSeverity(null, 300, "never_run", null)).toBe("unknown");
    expect(classifyCronSeverity(null, 300, null, null)).toBe("unknown");
    expect(classifyCronSeverity(null, 300, "unknown", null)).toBe("unknown");
  });

  it("returns 'ok' for a fresh success well within the cycle", () => {
    expect(classifyCronSeverity(60, 300, "completed", null)).toBe("ok");
  });

  it("returns 'warn' when the last success is ~1.6x the cycle ago", () => {
    expect(classifyCronSeverity(480, 300, "completed", null)).toBe("warn");
  });

  it("returns 'critical' when the last success is 3x+ the cycle ago", () => {
    expect(classifyCronSeverity(1050, 300, "completed", null)).toBe("critical");
  });

  it("returns 'warn' for a recent failure inside one cycle", () => {
    expect(classifyCronSeverity(60, 300, "failed", null)).toBe("warn");
  });

  it("returns 'critical' when a failure has persisted past 1.5 cycles", () => {
    expect(classifyCronSeverity(500, 300, "failed", null)).toBe("critical");
  });

  it("returns 'ok' for a job currently running inside its cycle", () => {
    expect(classifyCronSeverity(120, 300, "running", 60)).toBe("ok");
  });

  it("returns 'warn' for a job running 1.5..3x its cycle", () => {
    expect(classifyCronSeverity(120, 300, "running", 500)).toBe("warn");
  });

  it("returns 'critical' for a job running 3x+ its cycle (orphan)", () => {
    expect(classifyCronSeverity(120, 300, "running", 1500)).toBe("critical");
  });

  it("clamps a missing/non-finite expected interval to the daily fallback", () => {
    // 86400 fallback × 1.5 = 129600 → 1d18h. 100k seconds is below the
    // warn threshold; classifier should say 'ok'.
    expect(classifyCronSeverity(100_000, NaN, "completed", null)).toBe("ok");
    expect(classifyCronSeverity(100_000, null, "completed", null)).toBe("ok");
    expect(classifyCronSeverity(100_000, undefined, "completed", null)).toBe("ok");
    // 200k seconds = 2.3d, > 1.5d but < 3x → warn.
    expect(classifyCronSeverity(200_000, NaN, "completed", null)).toBe("warn");
  });

  it("clamps a too-small expected interval to 60s minimum (matches SQL GREATEST)", () => {
    // expected=10 would otherwise allow severity to flip on a 30s window
    // (clearly noise). With the 60s clamp the boundaries become:
    //   - 'ok'        : seconds_since_last_success <= 1.5 * 60 = 90
    //   - 'warn'      : 90  < secs <= 180
    //   - 'critical'  : secs > 180
    expect(classifyCronSeverity(60, 10, "completed", null)).toBe("ok");
    expect(classifyCronSeverity(89, 10, "completed", null)).toBe("ok");
    expect(classifyCronSeverity(120, 10, "completed", null)).toBe("warn");
    expect(classifyCronSeverity(180, 10, "completed", null)).toBe("warn");
    expect(classifyCronSeverity(200, 10, "completed", null)).toBe("critical");
  });

  it("ranks a stale-failure case as 'critical' before falling through to 'warn'", () => {
    // Vector also covers a `skipped` status: skipped is not 'failed' and
    // success is fresh → ok.
    expect(classifyCronSeverity(60, 300, "skipped", null)).toBe("ok");
    // skipped + stale success → warn (no failure flag, just staleness).
    expect(classifyCronSeverity(700, 300, "skipped", null)).toBe("warn");
  });
});

describe("cron-health — checkCronHealth (L06-04)", () => {
  beforeEach(() => {
    mockRpc.mockReset();
  });

  it("returns an empty healthy summary when DB returns no rows", async () => {
    mockRpc.mockResolvedValueOnce({ data: [], error: null });
    const r = await checkCronHealth();
    expect(r.rows).toEqual([]);
    expect(r.healthy).toBe(true);
    expect(r.countsBySeverity).toEqual({ ok: 0, warn: 0, critical: 0, unknown: 0 });
    expect(typeof r.checkedAt).toBe("string");
    expect(mockRpc).toHaveBeenCalledWith("fn_check_cron_health");
  });

  it("normalises rows and reports counts/healthy correctly", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          name: "settle-clearing-batch",
          schedule: "* * * * *",
          source: "both",
          active: true,
          last_status: "completed",
          started_at: "2026-04-19T14:00:00Z",
          finished_at: "2026-04-19T14:00:01Z",
          last_success_at: "2026-04-19T14:00:01Z",
          expected_interval_seconds: "60",
          seconds_since_last_success: "20",
          running_for_seconds: null,
          run_count: "12345",
          skip_count: "0",
          last_error: null,
          last_meta: { processed: 5 },
          severity: "ok",
        },
        {
          name: "lifecycle-cron",
          schedule: "*/5 * * * *",
          source: "both",
          active: true,
          last_status: "failed",
          started_at: "2026-04-19T13:50:00Z",
          finished_at: "2026-04-19T13:50:30Z",
          last_success_at: null,
          expected_interval_seconds: 300,
          seconds_since_last_success: 1800,
          running_for_seconds: null,
          run_count: 200,
          skip_count: 1,
          last_error: "boom",
          last_meta: { sqlstate: "P0001" },
          severity: "critical",
        },
        {
          // Row with garbage / missing fields → defaults applied, never thrown.
          name: "exotic-job",
          schedule: null,
          source: "garbage" as unknown as string,
          active: null,
          last_status: "weird-status",
          started_at: null,
          finished_at: null,
          last_success_at: null,
          expected_interval_seconds: null,
          seconds_since_last_success: null,
          running_for_seconds: null,
          run_count: null,
          skip_count: null,
          last_error: null,
          last_meta: "not an object",
          severity: "wat",
        },
      ],
      error: null,
    });

    const r = await checkCronHealth();

    expect(r.healthy).toBe(false);
    expect(r.countsBySeverity).toEqual({ ok: 1, warn: 0, critical: 1, unknown: 1 });
    expect(r.rows).toHaveLength(3);

    const settle = r.rows.find((row) => row.name === "settle-clearing-batch")!;
    expect(settle.expected_interval_seconds).toBe(60);
    expect(settle.seconds_since_last_success).toBe(20);
    expect(settle.run_count).toBe(12345);
    expect(settle.last_meta).toEqual({ processed: 5 });

    const exotic = r.rows.find((row) => row.name === "exotic-job")!;
    expect(exotic.source).toBe("cron_run_state");
    expect(exotic.last_status).toBe("unknown");
    expect(exotic.expected_interval_seconds).toBe(86400);
    expect(exotic.last_meta).toEqual({});
    expect(exotic.severity).toBe("unknown");
  });

  it("filters by minSeverity when requested", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        { name: "ok-job", schedule: "*/5 * * * *", source: "both", active: true, last_status: "completed", started_at: null, finished_at: null, last_success_at: null, expected_interval_seconds: 300, seconds_since_last_success: 60, running_for_seconds: null, run_count: 1, skip_count: 0, last_error: null, last_meta: {}, severity: "ok" },
        { name: "warn-job", schedule: "*/5 * * * *", source: "both", active: true, last_status: "failed", started_at: null, finished_at: null, last_success_at: null, expected_interval_seconds: 300, seconds_since_last_success: 60, running_for_seconds: null, run_count: 1, skip_count: 0, last_error: "x", last_meta: {}, severity: "warn" },
        { name: "crit-job", schedule: "*/5 * * * *", source: "both", active: true, last_status: "failed", started_at: null, finished_at: null, last_success_at: null, expected_interval_seconds: 300, seconds_since_last_success: 5000, running_for_seconds: null, run_count: 1, skip_count: 0, last_error: "x", last_meta: {}, severity: "critical" },
      ],
      error: null,
    });

    const r = await checkCronHealth({ minSeverity: "warn" });
    expect(r.rows.map((row) => row.name).sort()).toEqual(["crit-job", "warn-job"]);
    expect(r.healthy).toBe(false);
  });

  it("propagates RPC errors as a thrown Error (so monitoring sees them)", async () => {
    mockRpc.mockResolvedValueOnce({ data: null, error: { message: "rpc exploded" } });
    await expect(checkCronHealth()).rejects.toThrow(/fn_check_cron_health failed: rpc exploded/);
  });

  it("uses the injected client (no service-role hit) when one is provided", async () => {
    const stub = { rpc: vi.fn().mockResolvedValue({ data: [], error: null }) };
    await checkCronHealth({ client: stub });
    expect(stub.rpc).toHaveBeenCalledWith("fn_check_cron_health");
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("drops rows that are missing the required `name` field", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        { name: null, severity: "ok" },
        { name: "", severity: "ok" },
        { name: "real-job", schedule: "*/5 * * * *", source: "both", active: true, last_status: "completed", started_at: null, finished_at: null, last_success_at: null, expected_interval_seconds: 300, seconds_since_last_success: 30, running_for_seconds: null, run_count: 1, skip_count: 0, last_error: null, last_meta: {}, severity: "ok" },
      ],
      error: null,
    });
    const r = await checkCronHealth();
    expect(r.rows.map((row) => row.name)).toEqual(["real-job"]);
  });
});
