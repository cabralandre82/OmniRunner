import { test, expect } from "@playwright/test";

const AUTH_REDIRECT = /\/(login|auth|no-access|select-group)/;

function isRedirectedToAuth(url: string): boolean {
  return AUTH_REDIRECT.test(url);
}

test.describe("Business flow: Engagement", () => {
  test("navigate to /engagement and verify engagement dashboard or redirect", async ({
    page,
  }) => {
    await page.goto("/engagement");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Engajamento" })
    ).toBeVisible();
    await expect(
      page.getByText("Métricas de atividade e retenção dos atletas")
    ).toBeVisible();
    await expect(
      page.getByText(/DAU|WAU|MAU|Retenção|Corridas|Km/)
    ).toBeVisible();
  });

  test("navigate to /attendance or redirect", async ({ page }) => {
    await page.goto("/attendance");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Cumprimento dos Treinos|Treinos Prescritos|Treinos \(período\)|Taxa de conclusão/)
    ).toBeVisible();
  });

  test("navigate to /announcements or redirect", async ({ page }) => {
    await page.goto("/announcements");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Mural|Avisos|anúncios|announcements/)
    ).toBeVisible();
  });

  test("navigate to /communications or redirect", async ({ page }) => {
    await page.goto("/communications");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Comunicação|comunicação|Comunicações/)
    ).toBeVisible();
  });
});
