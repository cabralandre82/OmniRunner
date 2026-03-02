import { describe, it, expect, beforeEach, vi } from "vitest";
import { rateLimit } from "./rate-limit";

describe("rateLimit", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  it("allows requests within the limit", () => {
    const result = rateLimit("test-key-1", { maxRequests: 3, windowMs: 1000 });
    expect(result.allowed).toBe(true);
    expect(result.remaining).toBe(2);
  });

  it("tracks remaining requests accurately", () => {
    const key = "test-key-2";
    const opts = { maxRequests: 3, windowMs: 60000 };

    const r1 = rateLimit(key, opts);
    expect(r1.remaining).toBe(2);

    const r2 = rateLimit(key, opts);
    expect(r2.remaining).toBe(1);

    const r3 = rateLimit(key, opts);
    expect(r3.remaining).toBe(0);
  });

  it("blocks requests exceeding the limit", () => {
    const key = "test-key-3";
    const opts = { maxRequests: 2, windowMs: 60000 };

    rateLimit(key, opts);
    rateLimit(key, opts);
    const r3 = rateLimit(key, opts);

    expect(r3.allowed).toBe(false);
    expect(r3.remaining).toBe(0);
  });

  it("resets after the window expires", () => {
    const key = "test-key-4";
    const opts = { maxRequests: 1, windowMs: 1000 };

    const r1 = rateLimit(key, opts);
    expect(r1.allowed).toBe(true);

    const r2 = rateLimit(key, opts);
    expect(r2.allowed).toBe(false);

    vi.advanceTimersByTime(1001);

    const r3 = rateLimit(key, opts);
    expect(r3.allowed).toBe(true);
  });

  it("isolates different keys", () => {
    const opts = { maxRequests: 1, windowMs: 60000 };

    const r1 = rateLimit("key-a", opts);
    expect(r1.allowed).toBe(true);

    const r2 = rateLimit("key-b", opts);
    expect(r2.allowed).toBe(true);

    const r3 = rateLimit("key-a", opts);
    expect(r3.allowed).toBe(false);
  });

  it("returns correct resetAt timestamp", () => {
    const now = Date.now();
    const result = rateLimit("test-key-5", { maxRequests: 10, windowMs: 5000 });
    expect(result.resetAt).toBeGreaterThanOrEqual(now + 5000);
  });
});
