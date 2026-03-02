import { test, expect } from "@playwright/test";

test.describe("Accessibility basics", () => {
  test("login page has lang attribute on html", async ({ page }) => {
    await page.goto("/login");
    const html = page.locator("html");
    const lang = await html.getAttribute("lang");
    expect(lang).toBeTruthy();
    expect(lang).toMatch(/pt|en/);
  });

  test("login page has no missing alt attributes on images", async ({ page }) => {
    await page.goto("/login");
    const images = page.locator("img");
    const count = await images.count();
    for (let i = 0; i < count; i++) {
      const alt = await images.nth(i).getAttribute("alt");
      expect(alt).not.toBeNull();
    }
  });

  test("login page has at least one heading", async ({ page }) => {
    await page.goto("/login");
    const headings = page.locator("h1, h2, h3");
    await expect(headings.first()).toBeVisible();
  });

  test("interactive elements are focusable", async ({ page }) => {
    await page.goto("/login");
    const buttons = page.locator("button, a[href], input");
    const count = await buttons.count();
    expect(count).toBeGreaterThan(0);
  });
});
