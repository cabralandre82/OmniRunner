import { test, expect } from "@playwright/test";

test.describe("Content Security Policy", () => {
  test("responses include CSP header", async ({ request }) => {
    const res = await request.get("/api/health");
    const csp = res.headers()["content-security-policy"];
    expect(csp).toBeDefined();
    expect(csp).toContain("default-src");
    expect(csp).toContain("script-src");
  });

  test("responses include Strict-Transport-Security", async ({ request }) => {
    const res = await request.get("/api/health");
    const hsts = res.headers()["strict-transport-security"];
    expect(hsts).toBeDefined();
    expect(hsts).toContain("max-age");
  });

  test("responses include X-Content-Type-Options nosniff", async ({ request }) => {
    const res = await request.get("/api/health");
    expect(res.headers()["x-content-type-options"]).toBe("nosniff");
  });

  test("responses include Referrer-Policy", async ({ request }) => {
    const res = await request.get("/api/health");
    expect(res.headers()["referrer-policy"]).toBeDefined();
  });
});
