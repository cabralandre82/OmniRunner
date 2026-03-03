import { test, expect } from "@playwright/test";

const PORTAL_PAGES = [
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

const PUBLIC_PAGES = ["/login", "/no-access"];

test.describe("Page rendering — no 500 errors", () => {
  for (const path of [...PORTAL_PAGES, ...PUBLIC_PAGES]) {
    test(`${path} does not return 500`, async ({ page }) => {
      const jsErrors: string[] = [];
      page.on("pageerror", (err) => jsErrors.push(err.message));

      const response = await page.goto(path, { waitUntil: "commit" });
      const status = response?.status() ?? 0;

      expect(status).toBeLessThan(500);
    });
  }

  test("no uncaught JS errors on public pages", async ({ page }) => {
    const jsErrors: string[] = [];
    page.on("pageerror", (err) => jsErrors.push(err.message));

    for (const path of PUBLIC_PAGES) {
      await page.goto(path, { waitUntil: "domcontentloaded" });
    }

    expect(jsErrors).toEqual([]);
  });
});
