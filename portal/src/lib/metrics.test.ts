import { describe, it, expect, vi, beforeEach } from "vitest";
import { metrics, withMetrics, type MetricEvent } from "./metrics";

vi.mock("./logger", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

import { logger } from "./logger";

describe("metrics", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("increment logs a count metric", () => {
    metrics.increment("custody.deposit", { group_id: "g1" });
    expect(logger.info).toHaveBeenCalledWith(
      "metric:custody.deposit",
      expect.objectContaining({
        metric: "custody.deposit",
        value: 1,
        unit: "count",
        group_id: "g1",
      }),
    );
  });

  it("timing logs a ms metric", () => {
    metrics.timing("clearing.settle", 42, { settlement_id: "s1" });
    expect(logger.info).toHaveBeenCalledWith(
      "metric:clearing.settle",
      expect.objectContaining({
        metric: "clearing.settle",
        value: 42,
        unit: "ms",
      }),
    );
  });

  it("gauge logs a value metric", () => {
    metrics.gauge("custody.total_deposited", 50000, { group_id: "g2" });
    expect(logger.info).toHaveBeenCalledWith(
      "metric:custody.total_deposited",
      expect.objectContaining({
        value: 50000,
      }),
    );
  });

  it("record accepts full MetricEvent", () => {
    const event: MetricEvent = {
      name: "swap.executed",
      value: 1000,
      unit: "usd",
      tags: { seller: "g1", buyer: "g2" },
    };
    metrics.record(event);
    expect(logger.info).toHaveBeenCalledTimes(1);
  });
});

describe("withMetrics", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("records timing and success on success", async () => {
    const result = await withMetrics("test.op", async () => "ok");
    expect(result).toBe("ok");
    expect(logger.info).toHaveBeenCalledWith(
      "metric:test.op.started",
      expect.objectContaining({ value: 1 }),
    );
    expect(logger.info).toHaveBeenCalledWith(
      "metric:test.op.success",
      expect.objectContaining({ value: 1 }),
    );
    expect(logger.info).toHaveBeenCalledWith(
      "metric:test.op.duration",
      expect.objectContaining({ unit: "ms" }),
    );
  });

  it("records error metric on failure", async () => {
    await expect(
      withMetrics("test.fail", async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");

    expect(logger.info).toHaveBeenCalledWith(
      "metric:test.fail.error",
      expect.objectContaining({ value: 1 }),
    );
  });

  it("passes tags through", async () => {
    await withMetrics("tagged.op", async () => 42, { env: "test" });
    expect(logger.info).toHaveBeenCalledWith(
      "metric:tagged.op.started",
      expect.objectContaining({ env: "test" }),
    );
  });
});
