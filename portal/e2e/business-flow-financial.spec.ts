import { test, expect } from "@playwright/test";

const AUTH_REDIRECT = /\/(login|auth|no-access|select-group)/;

function isRedirectedToAuth(url: string): boolean {
  return AUTH_REDIRECT.test(url);
}

test.describe("Business flow: Financial", () => {
  test("navigate to /financial and verify dashboard KPIs or redirect", async ({
    page,
  }) => {
    await page.goto("/financial");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Dashboard Financeiro" })
    ).toBeVisible();
    await expect(
      page.getByText("Visão geral da saúde financeira do grupo")
    ).toBeVisible();
    await expect(
      page.getByText(/Receita|Assinantes|Inadimplentes|Crescimento/)
    ).toBeVisible();
  });

  test("navigate to /financial/plans or redirect", async ({ page }) => {
    await page.goto("/financial/plans");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Planos|planos|configurar/)
    ).toBeVisible();
  });

  test("navigate to /financial/subscriptions or redirect", async ({
    page,
  }) => {
    await page.goto("/financial/subscriptions");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Assinaturas|assinaturas/)
    ).toBeVisible();
  });

  test("navigate to /financial/webhook-events (Histórico de Cobranças) or redirect", async ({
    page,
  }) => {
    await page.goto("/financial/webhook-events");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Histórico de Cobranças|cobranças|pagamentos/)
    ).toBeVisible();
  });
});
