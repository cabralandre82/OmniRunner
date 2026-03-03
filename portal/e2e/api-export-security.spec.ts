import { test, expect } from "@playwright/test";

const EXPORT_ROUTES = [
  "/api/export/engagement",
  "/api/export/alerts",
  "/api/export/announcements",
  "/api/export/crm",
  "/api/export/athletes",
  "/api/export/financial",
  "/api/export/attendance",
];

const VALID_UNAUTH_CODES = [301, 302, 303, 307, 308, 401, 403];

test.describe("Export API security — unauthenticated requests", () => {
  for (const route of EXPORT_ROUTES) {
    test(`GET ${route} blocks unauthenticated access`, async ({ request }) => {
      const res = await request.get(`${route}?groupId=test`, {
        maxRedirects: 0,
      });
      expect(VALID_UNAUTH_CODES).toContain(res.status());
    });
  }

  test("no export route returns 200 without auth", async ({ request }) => {
    for (const route of EXPORT_ROUTES) {
      const res = await request.get(`${route}?groupId=test`, {
        maxRedirects: 0,
      });
      expect(res.status()).not.toBe(200);
    }
  });
});
