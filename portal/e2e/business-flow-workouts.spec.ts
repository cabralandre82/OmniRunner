import { test, expect } from "@playwright/test";

const AUTH_REDIRECT = /\/(login|auth|no-access|select-group)/;

function isRedirectedToAuth(url: string): boolean {
  return AUTH_REDIRECT.test(url);
}

test.describe("Business flow: Workouts", () => {
  test("navigate to /workouts and verify workout templates list or redirect", async ({
    page,
  }) => {
    await page.goto("/workouts");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Templates de Treino" })
    ).toBeVisible();
    await expect(
      page.getByText("Gerencie os templates de treino do grupo")
    ).toBeVisible();
    await expect(
      page.getByText(/Nome|Descrição|Blocos|Distância|Novo Template/)
    ).toBeVisible();
  });

  test("navigate to /workouts/new and verify form fields or redirect", async ({
    page,
  }) => {
    await page.goto("/workouts/new");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByText(/Voltar aos templates|Novo Template/)
    ).toBeVisible();
    await expect(
      page.getByText(/Nome do template|Descrição|Bloco|Aquecimento|Intervalo/)
    ).toBeVisible();
  });

  test("navigate to /workouts/assign or redirect", async ({ page }) => {
    await page.goto("/workouts/assign");
    await page.waitForLoadState("networkidle");
    const url = page.url();

    if (isRedirectedToAuth(url)) {
      expect(url).toMatch(AUTH_REDIRECT);
      return;
    }

    await expect(
      page.getByRole("heading", { name: "Atribuir Treinos" })
    ).toBeVisible();
    await expect(
      page.getByText("Selecione atletas, escolha um template e defina a data")
    ).toBeVisible();
  });
});
