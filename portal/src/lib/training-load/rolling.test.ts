import { describe, expect, it } from "vitest";
import {
  buildLoadSeries,
  classifyTrainingZone,
  computeCtlRampRate,
  rollupDailyTss,
  sessionsToSeries,
} from "./rolling";

const DAY_MS = 86_400_000;
const BASE = Date.UTC(2026, 0, 1);

describe("training-load / rolling", () => {
  it("aggregates TSS per day and ignores non-positive entries", () => {
    const daily = rollupDailyTss({
      sessions: [
        { startedAt: BASE + 0 * DAY_MS, tss: 60 },
        { startedAt: BASE + 0 * DAY_MS, tss: 40 },
        { startedAt: BASE + 1 * DAY_MS, tss: 0 },
        { startedAt: BASE + 2 * DAY_MS, tss: 150 },
      ],
    });
    expect(daily).toEqual([
      { day: "2026-01-01", tssSum: 100, sessionCount: 2 },
      { day: "2026-01-03", tssSum: 150, sessionCount: 1 },
    ]);
  });

  it("CTL and ATL converge monotonically toward a steady TSS", () => {
    const daily = Array.from({ length: 60 }, (_, i) => ({
      day: new Date(BASE + i * DAY_MS).toISOString().slice(0, 10),
      tssSum: 50,
      sessionCount: 1,
    }));
    const series = buildLoadSeries({
      from: "2026-01-01",
      to: "2026-03-01",
      dailyLoad: daily,
    });
    expect(series.length).toBe(60);
    expect(series[0].ctl).toBeLessThan(series[59].ctl);
    expect(series[59].ctl).toBeLessThan(50);
    expect(series[59].atl).toBeGreaterThan(series[59].ctl);
    expect(series[59].atl).toBeLessThanOrEqual(50);
  });

  it("TSB is CTL minus ATL", () => {
    const series = buildLoadSeries({
      from: "2026-01-01",
      to: "2026-01-10",
      dailyLoad: [
        { day: "2026-01-01", tssSum: 80, sessionCount: 1 },
        { day: "2026-01-05", tssSum: 200, sessionCount: 1 },
      ],
    });
    for (const point of series) {
      expect(Math.abs(point.tsb - (point.ctl - point.atl))).toBeLessThanOrEqual(0.15);
    }
  });

  it("honours seed CTL/ATL values", () => {
    const series = buildLoadSeries({
      from: "2026-01-01",
      to: "2026-01-07",
      dailyLoad: [],
      seedCtl: 50,
      seedAtl: 60,
    });
    expect(series[0].ctl).toBeCloseTo(50 - 50 / 42, 1);
    expect(series[0].atl).toBeCloseTo(60 - 60 / 7, 1);
    expect(series[6].ctl).toBeLessThan(series[0].ctl);
  });

  it("rejects non-positive time constants", () => {
    expect(() =>
      buildLoadSeries({
        from: "2026-01-01",
        to: "2026-01-02",
        dailyLoad: [],
        ctlTauDays: 0,
      }),
    ).toThrow();
  });

  it("rejects inverted date ranges", () => {
    expect(() =>
      buildLoadSeries({
        from: "2026-01-10",
        to: "2026-01-01",
        dailyLoad: [],
      }),
    ).toThrow();
  });

  it("classifies training zones by TSB bands", () => {
    expect(classifyTrainingZone(-50)).toBe("high_risk");
    expect(classifyTrainingZone(-20)).toBe("overreaching");
    expect(classifyTrainingZone(0)).toBe("productive");
    expect(classifyTrainingZone(10)).toBe("optimal");
    expect(classifyTrainingZone(25)).toBe("rest");
  });

  it("computes CTL ramp rate over a sliding window", () => {
    const daily = Array.from({ length: 30 }, (_, i) => ({
      day: new Date(BASE + i * DAY_MS).toISOString().slice(0, 10),
      tssSum: 80,
      sessionCount: 1,
    }));
    const series = buildLoadSeries({
      from: "2026-01-01",
      to: "2026-01-30",
      dailyLoad: daily,
    });
    const ramp = computeCtlRampRate({ series });
    expect(ramp).toBeGreaterThan(0);
    expect(ramp).toBeLessThan(80);
  });

  it("returns 0 ramp when series is too short", () => {
    const ramp = computeCtlRampRate({
      series: [
        { day: "2026-01-01", ctl: 30, atl: 30, tsb: 0, dailyTss: 0 },
      ],
    });
    expect(ramp).toBe(0);
  });

  it("end-to-end: sessionsToSeries wires rollup and series", () => {
    const out = sessionsToSeries(
      [
        { id: "s1", athleteUserId: "a", startedAt: BASE, durationSec: 3600, tss: 50 },
        { id: "s2", athleteUserId: "a", startedAt: BASE + 2 * DAY_MS, durationSec: 3600, tss: 60 },
      ],
      { from: "2026-01-01", to: "2026-01-05" },
    );
    expect(out).toHaveLength(5);
    expect(out.map((p) => p.day)).toEqual([
      "2026-01-01",
      "2026-01-02",
      "2026-01-03",
      "2026-01-04",
      "2026-01-05",
    ]);
    expect(out[0].dailyTss).toBe(50);
    expect(out[2].dailyTss).toBe(60);
  });
});
