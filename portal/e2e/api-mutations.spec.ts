import { test, expect } from "@playwright/test";

test.describe("API mutation protection", () => {
  const mutationRoutes = [
    "/api/distribute-coins",
    "/api/auto-topup",
    "/api/gateway-preference",
    "/api/billing-portal",
    "/api/team/invite",
    "/api/team/remove",
  ];

  for (const route of mutationRoutes) {
    test(`POST ${route} requires authentication`, async ({ request }) => {
      const res = await request.post(route, {
        data: {},
        headers: { "Content-Type": "application/json" },
      });
      expect(res.status()).toBeGreaterThanOrEqual(400);
      expect(res.status()).toBeLessThan(500);
    });
  }

  test("GET /api/health is publicly accessible", async ({ request }) => {
    const res = await request.get("/api/health");
    expect(res.status()).toBe(200);
  });
});
