import { test, expect } from "@playwright/test";

test.describe("Public navigation", () => {
  test("root redirects to login or dashboard", async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    expect(page.url()).toMatch(/\/(login|auth|dashboard)/);
  });

  test("404 page renders for unknown routes", async ({ page }) => {
    const res = await page.goto("/this-route-does-not-exist-abc123");
    expect(res?.status()).toBe(404);
  });
});
