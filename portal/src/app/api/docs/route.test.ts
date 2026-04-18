import { describe, it, expect } from "vitest";
import { GET } from "./route";

/**
 * L14-03 — Self-host Swagger-UI (sem unpkg).
 *
 * Garantias testadas:
 *  - Nenhuma tag <script> ou <link> aponta para CDN externo (unpkg, jsdelivr,
 *    cdnjs, Google Fonts, etc).
 *  - Assets são servidos a partir de `/vendor/swagger-ui/*` (same-origin).
 *  - Headers defensivos presentes (Cache-Control: no-store, X-Content-Type-Options: nosniff).
 */

describe("GET /api/docs — L14-03 supply chain hardening", () => {
  it("retorna 200 com HTML e headers defensivos", async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toMatch(/text\/html/);
    expect(res.headers.get("Cache-Control")).toBe("no-store");
    expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(res.headers.get("Referrer-Policy")).toBe("no-referrer");
  });

  it("não referencia nenhum CDN externo (unpkg, jsdelivr, cdnjs, etc)", async () => {
    const res = await GET();
    const html = await res.text();

    const forbiddenHosts = [
      "unpkg.com",
      "cdn.jsdelivr.net",
      "cdnjs.cloudflare.com",
      "ajax.googleapis.com",
      "fonts.googleapis.com",
      "fonts.gstatic.com",
      "maxcdn.bootstrapcdn.com",
      "stackpath.bootstrapcdn.com",
    ];

    for (const host of forbiddenHosts) {
      expect(html, `HTML deve não conter referência a ${host}`).not.toContain(host);
    }

    const externalPattern = /(src|href)=\s*["']https?:\/\//i;
    expect(html, "Nenhum src/href pode apontar para URL absoluta http(s)").not.toMatch(
      externalPattern
    );
  });

  it("carrega Swagger-UI a partir de /vendor/swagger-ui/ (same-origin)", async () => {
    const res = await GET();
    const html = await res.text();

    expect(html).toContain('src="/vendor/swagger-ui/swagger-ui-bundle.js"');
    expect(html).toContain('src="/vendor/swagger-ui/swagger-ui-standalone-preset.js"');
    expect(html).toContain('href="/vendor/swagger-ui/swagger-ui.css"');
  });

  it("aponta Swagger-UI para o openapi.json correto", async () => {
    const res = await GET();
    const html = await res.text();
    expect(html).toContain('url: "/openapi.json"');
  });

  it("não expõe tokens/secrets inline", async () => {
    const res = await GET();
    const html = await res.text();

    expect(html).not.toMatch(/eyJ[A-Za-z0-9_-]{20,}/);
    expect(html).not.toMatch(/sk_(live|test)_[A-Za-z0-9]{20,}/);
    expect(html).not.toMatch(/service_role/i);
  });
});
