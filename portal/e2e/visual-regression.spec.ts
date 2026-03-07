import { test, expect } from "@playwright/test";

const VIEWPORT = { width: 1280, height: 720 };

const PAGES = [
  { path: "/login", name: "login" },
  { path: "/dashboard", name: "dashboard" },
  { path: "/athletes", name: "athletes" },
  { path: "/financial", name: "financial" },
  { path: "/workouts", name: "workouts" },
  { path: "/settings", name: "settings" },
];

test.describe("Visual regression", () => {
  test.use({ viewport: VIEWPORT });

  for (const { path, name } of PAGES) {
    test(`${name} page matches baseline`, async ({ page }) => {
      await page.goto(path, { waitUntil: "networkidle" });
      // Handle auth redirect: if redirected to login/auth, we screenshot that page
      await page.waitForURL(/\/(login|auth|dashboard|athletes|financial|workouts|settings|select-group)/, { timeout: 15000 });
      await expect(page).toHaveScreenshot(`${name}.png`);
    });
  }
});
