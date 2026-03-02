import { describe, it, expect, vi, beforeEach } from "vitest";
import { logger } from "./logger";

describe("logger", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("logs info as structured JSON", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    logger.info("test message", { userId: "123" });

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.level).toBe("info");
    expect(parsed.msg).toBe("test message");
    expect(parsed.userId).toBe("123");
    expect(parsed.ts).toBeDefined();
  });

  it("logs warnings", () => {
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    logger.warn("something off");

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.level).toBe("warn");
  });

  it("logs errors with error details", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const err = new Error("boom");
    logger.error("failed", err, { action: "test" });

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.level).toBe("error");
    expect(parsed.error).toBe("boom");
    expect(parsed.stack).toContain("Error: boom");
    expect(parsed.action).toBe("test");
  });

  it("handles non-Error objects in error field", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    logger.error("failed", "string error");

    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.error).toBe("string error");
  });
});
