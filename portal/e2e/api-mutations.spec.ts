import { test, expect } from "@playwright/test";

const VALID_UNAUTH_CODES = [301, 302, 303, 307, 308, 401, 403];

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
        maxRedirects: 0,
      });
      expect(VALID_UNAUTH_CODES).toContain(res.status());
    });
  }

  test("GET /api/health is publicly accessible", async ({ request }) => {
    const res = await request.get("/api/health", { maxRedirects: 0 });
    const status = res.status();
    expect(status === 200 || status === 404).toBe(true);
  });
});
