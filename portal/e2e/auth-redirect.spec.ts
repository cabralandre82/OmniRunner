import { test, expect } from "@playwright/test";

test.describe("Authentication redirects", () => {
  test("unauthenticated user on /dashboard is redirected to login", async ({
    page,
  }) => {
    await page.goto("/dashboard");
    await page.waitForURL(/\/(login|auth)/);
    expect(page.url()).toMatch(/\/(login|auth)/);
  });

  test("unauthenticated user on /athletes is redirected to login", async ({
    page,
  }) => {
    await page.goto("/athletes");
    await page.waitForURL(/\/(login|auth)/);
    expect(page.url()).toMatch(/\/(login|auth)/);
  });

  test("unauthenticated user on /settings is redirected to login", async ({
    page,
  }) => {
    await page.goto("/settings");
    await page.waitForURL(/\/(login|auth)/);
    expect(page.url()).toMatch(/\/(login|auth)/);
  });
});
