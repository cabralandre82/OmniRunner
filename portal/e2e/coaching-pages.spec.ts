import { test, expect } from "@playwright/test";

const COACHING_PAGES = [
  "/dashboard",
  "/engagement",
  "/attendance-analytics",
  "/risk",
  "/crm",
  "/crm/at-risk",
  "/announcements",
  "/communications",
  "/workouts",
  "/workouts/assignments",
  "/workouts/analytics",
  "/financial",
  "/financial/plans",
  "/financial/subscriptions",
  "/exports",
  "/executions",
  "/settings",
];

test.describe("Coaching pages — unauthenticated access", () => {
  for (const path of COACHING_PAGES) {
    test(`${path} redirects to login or blocks access (no 500)`, async ({
      page,
    }) => {
      const response = await page.goto(path);
      const status = response?.status() ?? 0;

      expect(status).toBeLessThan(500);

      const url = page.url();
      const redirectedToLogin = /\/(login|auth|no-access|select-group)/.test(
        url
      );
      const blockedWithClientError = status >= 400 && status < 500;

      expect(redirectedToLogin || blockedWithClientError).toBe(true);
    });
  }

  test("no coaching page returns a server error", async ({ page }) => {
    for (const path of COACHING_PAGES) {
      const response = await page.goto(path, { waitUntil: "commit" });
      expect(response?.status()).toBeLessThan(500);
    }
  });
});
