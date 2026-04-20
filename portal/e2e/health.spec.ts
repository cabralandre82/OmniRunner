import { test, expect } from "@playwright/test";

/**
 * L06-02 — the public /api/health endpoint must expose ONLY
 * { status, ts }. Any leak of invariant counts, latency, or the
 * `checks` breakdown would regress the info-disclosure fix.
 */
test.describe("Health check (public)", () => {
  test("GET /api/health returns 200/503 with a stripped payload and no leakage", async ({
    request,
  }) => {
    const res = await request.get("/api/health");
    const status = res.status();

    if (status === 404) {
      return;
    }

    expect([200, 503]).toContain(status);
    const body = await res.json();
    expect(body).toHaveProperty("status");
    expect(body).toHaveProperty("ts");
    expect(["ok", "degraded", "down"]).toContain(body.status);

    expect(body).not.toHaveProperty("checks");
    expect(body).not.toHaveProperty("latencyMs");
    expect(body).not.toHaveProperty("latency_ms");
    expect(body).not.toHaveProperty("invariantCount");
    expect(body).not.toHaveProperty("invariant_count");
    expect(Object.keys(body).sort()).toEqual(["status", "ts"]);
  });

  test("GET /api/platform/health requires authentication", async ({
    request,
  }) => {
    const res = await request.get("/api/platform/health");
    expect([401, 403, 404]).toContain(res.status());
    if (res.status() === 401 || res.status() === 403) {
      const body = await res.json();
      expect(body.ok).toBe(false);
      expect(body.error?.code).toBe("UNAUTHORIZED");
    }
  });
});
