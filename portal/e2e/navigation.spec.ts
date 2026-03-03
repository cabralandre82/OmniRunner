import { test, expect } from "@playwright/test";

test.describe("Public navigation", () => {
  test("root redirects to login or dashboard", async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    expect(page.url()).toMatch(/\/(login|auth|dashboard)/);
  });

  test("unknown route redirects to login (protected app)", async ({
    page,
  }) => {
    const res = await page.goto("/this-route-does-not-exist-abc123");
    const url = page.url();
    const status = res?.status() ?? 0;
    const redirectedToLogin = /\/(login|auth|no-access)/.test(url);
    expect(status === 404 || redirectedToLogin).toBe(true);
  });
});
