import { test, expect } from "@playwright/test";

const AUTH_REDIRECT = /\/(login|auth|no-access|select-group)/;

function isRedirectedToAuth(url: string): boolean {
  return AUTH_REDIRECT.test(url);
}

test.describe("Business flow: OmniCoins", () => {
  test("navigate to /custody (Saldo OmniCoins) or redirect", async ({
    page,
  }) => {
    await page.goto("/custody");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Saldo OmniCoins" })
    ).toBeVisible();
  });

  test("navigate to /clearing (Transferências OmniCoins) or redirect", async ({
    page,
  }) => {
    await page.goto("/clearing");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Transferências OmniCoins" })
    ).toBeVisible();
  });

  test("navigate to /distributions (Distribuir OmniCoins) or redirect", async ({
    page,
  }) => {
    await page.goto("/distributions");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Distribuição de OmniCoins" })
    ).toBeVisible();
    await expect(
      page.getByText(/Saldo Disponível|Total Distribuído|Histórico/)
    ).toBeVisible();
  });

  test("navigate to /swap or redirect", async ({ page }) => {
    await page.goto("/swap");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Swap de Lastro" })
    ).toBeVisible();
    await expect(
      page.getByText(/Disponivel para Swap|Volume|Taxa|Mercado B2B/)
    ).toBeVisible();
  });
});
