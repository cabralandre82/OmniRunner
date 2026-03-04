import { test, expect } from "@playwright/test";

test.describe("Delivery page", () => {
  test("renders delivery page with correct title", async ({ page }) => {
    // Navigate to delivery page - will need auth setup
    await page.goto("/delivery");
    await expect(page.getByText("Entrega de Treinos")).toBeVisible();
  });

  test("shows empty state when no items", async ({ page }) => {
    await page.goto("/delivery");
    await expect(page.getByText("Nenhum item de entrega encontrado")).toBeVisible();
  });

  test("TP nav item hidden when flag off", async ({ page }) => {
    await page.goto("/dashboard");
    await expect(page.getByText("TrainingPeaks")).not.toBeVisible();
  });
});
