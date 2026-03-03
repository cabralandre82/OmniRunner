import { test, expect } from "@playwright/test";

const MOBILE_VIEWPORT = { width: 375, height: 667 };

const PAGES_TO_TEST = ["/login", "/dashboard", "/crm", "/announcements"];

test.describe("Responsive rendering — mobile viewport", () => {
  test.use({ viewport: MOBILE_VIEWPORT });

  for (const path of PAGES_TO_TEST) {
    test(`${path} renders without JS errors on mobile`, async ({ page }) => {
      const jsErrors: string[] = [];
      page.on("pageerror", (err) => jsErrors.push(err.message));

      const response = await page.goto(path, { waitUntil: "domcontentloaded" });
      const status = response?.status() ?? 0;

      expect(status).toBeLessThan(500);
      expect(jsErrors).toEqual([]);
    });
  }

  test("login page is usable on mobile", async ({ page }) => {
    await page.goto("/login", { waitUntil: "domcontentloaded" });

    const body = page.locator("body");
    await expect(body).toBeVisible();

    const hasNoHorizontalOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth <= window.innerWidth + 5;
    });
    expect(hasNoHorizontalOverflow).toBe(true);
  });
});
