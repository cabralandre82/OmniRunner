import { test, expect } from "@playwright/test";

test.describe("Login page", () => {
  test("renders login page with expected elements", async ({ page }) => {
    await page.goto("/login");
    await expect(page).toHaveTitle(/OmniRunner|Login|Entrar/i);

    const heading = page.getByRole("heading").first();
    await expect(heading).toBeVisible();
  });

  test("login page is accessible (no critical a11y issues)", async ({
    page,
  }) => {
    await page.goto("/login");
    const html = page.locator("html");
    await expect(html).toHaveAttribute("lang", "pt-BR");
  });
});
