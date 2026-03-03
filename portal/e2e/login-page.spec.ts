import { test, expect } from "@playwright/test";

test.describe("Login page", () => {
  test("renders login page without crashing", async ({ page }) => {
    await page.goto("/login");
    await page.waitForLoadState("domcontentloaded");
    const body = await page.textContent("body");
    expect(body).toBeTruthy();
  });

  test("login page has a heading", async ({ page }) => {
    await page.goto("/login");
    const heading = page.getByRole("heading").first();
    await expect(heading).toBeVisible({ timeout: 10000 });
  });
});
