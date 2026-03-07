import { test, expect } from "@playwright/test";

const AUTH_REDIRECT = /\/(login|auth|no-access|select-group)/;

function isRedirectedToAuth(url: string): boolean {
  return AUTH_REDIRECT.test(url);
}

test.describe("Business flow: Athletes", () => {
  test("navigate to /athletes and verify athlete list or redirect", async ({
    page,
  }) => {
    await page.goto("/athletes");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Atletas" })
    ).toBeVisible();
    await expect(
      page.getByText("Todos os atletas vinculados à assessoria")
    ).toBeVisible();
    await expect(
      page.getByText(/Total|Ativos|Verificados|Km totais/)
    ).toBeVisible();
  });

  test("click athlete to view details and verify CRM data or redirect", async ({
    page,
  }) => {
    await page.goto("/athletes");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    const athleteLink = page.locator('a[href^="/athletes/"]').first();
    const count = await athleteLink.count();
    if (count === 0) {
      await expect(
        page.getByText(/Nenhum atleta|atletas vinculados/)
      ).toBeVisible();
      return;
    }

    await athleteLink.click();
    await page.waitForLoadState("networkidle");

    const detailUrl = page.url();
    if (isRedirectedToAuth(detailUrl)) {
      expect(detailUrl).toMatch(AUTH_REDIRECT);
      return;
    }

    expect(detailUrl).toMatch(/\/athletes\/[a-f0-9-]+/);
    await expect(
      page.getByRole("heading", { level: 1 })
    ).toBeVisible();
    await expect(
      page.getByText(/Level|Streak|Badges|Corridas|XP|Resumo/)
    ).toBeVisible();
  });
});
