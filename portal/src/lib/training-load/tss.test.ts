import { describe, expect, it } from "vitest";
import { clampIf, clampTss, computeSessionTss, hrIntensityFactor } from "./tss";

describe("training-load / tss", () => {
  it("returns zero TSS for non-positive duration", () => {
    const b = computeSessionTss(
      { id: "s1", athleteUserId: "a", startedAt: 0, durationSec: 0 },
      {},
    );
    expect(b.tss).toBe(0);
    expect(b.intensityFactor).toBe(0);
    expect(b.method).toBe("fallback");
  });

  it("rTSS: 1-hour at threshold pace yields TSS 100", () => {
    const b = computeSessionTss(
      {
        id: "s1",
        athleteUserId: "a",
        startedAt: 0,
        durationSec: 3600,
        normalizedGradedPaceSecPerKm: 240,
      },
      { runFtpPaceSecPerKm: 240 },
    );
    expect(b.method).toBe("rTSS");
    expect(b.intensityFactor).toBeCloseTo(1.0, 4);
    expect(b.tss).toBeCloseTo(100, 1);
  });

  it("rTSS: slower pace reduces TSS quadratically", () => {
    const slow = computeSessionTss(
      {
        id: "s",
        athleteUserId: "a",
        startedAt: 0,
        durationSec: 3600,
        normalizedGradedPaceSecPerKm: 300,
      },
      { runFtpPaceSecPerKm: 240 },
    );
    expect(slow.method).toBe("rTSS");
    expect(slow.intensityFactor).toBeCloseTo(0.8, 3);
    expect(slow.tss).toBeCloseTo(64, 1);
  });

  it("hrTSS: threshold HR for one hour yields TSS 100", () => {
    const b = computeSessionTss(
      {
        id: "s",
        athleteUserId: "a",
        startedAt: 0,
        durationSec: 3600,
        avgHeartRateBpm: 170,
      },
      { heartRateThresholdBpm: 170 },
    );
    expect(b.method).toBe("hrTSS");
    expect(b.intensityFactor).toBeCloseTo(1.0, 2);
    expect(b.tss).toBeCloseTo(100, 1);
  });

  it("hrTSS: easy HR produces lower IF than rTSS ratio alone", () => {
    const b = computeSessionTss(
      {
        id: "s",
        athleteUserId: "a",
        startedAt: 0,
        durationSec: 3600,
        avgHeartRateBpm: 119,
      },
      { heartRateThresholdBpm: 170 },
    );
    expect(b.method).toBe("hrTSS");
    expect(b.intensityFactor).toBeLessThan(0.75);
    expect(b.intensityFactor).toBeGreaterThan(0.55);
  });

  it("prefers rTSS when both pace and HR are available", () => {
    const b = computeSessionTss(
      {
        id: "s",
        athleteUserId: "a",
        startedAt: 0,
        durationSec: 3600,
        normalizedGradedPaceSecPerKm: 240,
        avgHeartRateBpm: 170,
      },
      { runFtpPaceSecPerKm: 240, heartRateThresholdBpm: 170 },
    );
    expect(b.method).toBe("rTSS");
  });

  it("falls back to IF 0.70 when no inputs are available", () => {
    const b = computeSessionTss(
      { id: "s", athleteUserId: "a", startedAt: 0, durationSec: 3600 },
      {},
    );
    expect(b.method).toBe("fallback");
    expect(b.intensityFactor).toBeCloseTo(0.7, 3);
    expect(b.tss).toBeCloseTo(49, 1);
  });

  it("clamps pathologically high IF at IF_MAX", () => {
    expect(clampIf(5)).toBeLessThanOrEqual(1.3);
    expect(clampIf(-1)).toBe(0);
    expect(clampIf(NaN)).toBe(0);
  });

  it("clamps pathologically high TSS at TSS_MAX", () => {
    expect(clampTss(99999)).toBeLessThanOrEqual(500);
    expect(clampTss(-5)).toBe(0);
  });

  it("hrIntensityFactor monotonically increasing", () => {
    expect(hrIntensityFactor(0.5)).toBeLessThan(hrIntensityFactor(0.8));
    expect(hrIntensityFactor(0.8)).toBeLessThan(hrIntensityFactor(1.0));
    expect(hrIntensityFactor(1.0)).toBeCloseTo(1.0, 4);
  });
});
