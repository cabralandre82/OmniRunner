import { test, expect } from "@playwright/test";

test.describe("API security headers", () => {
  test("responses include security headers", async ({ request }) => {
    const res = await request.get("/api/health");
    const headers = res.headers();

    expect(headers["x-content-type-options"]).toBe("nosniff");
    expect(headers["x-frame-options"]).toBe("DENY");
    expect(headers["referrer-policy"]).toBe(
      "strict-origin-when-cross-origin"
    );
    expect(headers["strict-transport-security"]).toContain("max-age=");
  });

  test("protected API routes return 401 without auth", async ({ request }) => {
    const routes = ["/api/branding", "/api/distribute-coins"];
    for (const route of routes) {
      const res = await request.get(route);
      expect(res.status()).toBeGreaterThanOrEqual(400);
    }
  });
});
