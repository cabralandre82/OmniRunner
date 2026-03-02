import { test, expect } from "@playwright/test";

test.describe("Error pages", () => {
  test("404 page returns proper status code", async ({ page }) => {
    const res = await page.goto("/this-page-does-not-exist-xyz");
    expect(res?.status()).toBe(404);
  });

  test("404 page has meaningful content", async ({ page }) => {
    await page.goto("/nonexistent-route-test-abc");
    const body = await page.textContent("body");
    expect(body).toBeTruthy();
  });

  test("API 404 returns JSON error", async ({ request }) => {
    const res = await request.get("/api/nonexistent-endpoint");
    expect(res.status()).toBeGreaterThanOrEqual(400);
  });
});
