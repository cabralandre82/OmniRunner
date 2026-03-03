import { test, expect } from "@playwright/test";

const VALID_UNAUTH_CODES = [301, 302, 303, 307, 308, 401, 403];

test.describe("API security", () => {
  test("protected API routes block unauthenticated access", async ({
    request,
  }) => {
    const routes = ["/api/branding", "/api/distribute-coins"];
    for (const route of routes) {
      const res = await request.get(route, { maxRedirects: 0 });
      expect(VALID_UNAUTH_CODES).toContain(res.status());
    }
  });
});
