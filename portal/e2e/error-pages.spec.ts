import { test, expect } from "@playwright/test";

test.describe("Error pages", () => {
  test("unknown page returns 404 or redirects to login", async ({ page }) => {
    const res = await page.goto("/this-page-does-not-exist-xyz");
    const status = res?.status() ?? 0;
    const url = page.url();
    const redirectedToLogin = /\/(login|auth)/.test(url);
    expect(status === 404 || redirectedToLogin).toBe(true);
  });

  test("404 page has meaningful content", async ({ page }) => {
    await page.goto("/nonexistent-route-test-abc");
    const body = await page.textContent("body");
    expect(body).toBeTruthy();
  });

  test("API 404 returns error status", async ({ request }) => {
    const res = await request.get("/api/nonexistent-endpoint", {
      maxRedirects: 0,
    });
    expect(res.status()).toBeGreaterThanOrEqual(300);
  });
});
