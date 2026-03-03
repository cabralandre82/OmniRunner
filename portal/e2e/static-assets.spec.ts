import { test, expect } from "@playwright/test";

test.describe("Static assets", () => {
  test("manifest.webmanifest is accessible", async ({ request }) => {
    const res = await request.get("/manifest.webmanifest");
    const status = res.status();
    expect(status).toBeLessThan(500);
  });

  test("CSS and JS bundles referenced by login page load successfully", async ({
    page,
  }) => {
    const failedAssets: string[] = [];

    page.on("response", (response) => {
      const url = response.url();
      const isAsset =
        url.includes("/_next/static/") &&
        (url.endsWith(".js") || url.endsWith(".css"));
      if (isAsset && response.status() >= 400) {
        failedAssets.push(`${response.status()} ${url}`);
      }
    });

    await page.goto("/login", { waitUntil: "networkidle" });

    expect(failedAssets).toEqual([]);
  });
});
