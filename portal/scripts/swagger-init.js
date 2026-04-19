// Omni Runner — Swagger UI bootstrap (L01-38).
//
// Externalised from `app/api/docs/route.ts` so the page can ship under
// the strict CSP `script-src 'self' 'nonce-…' 'strict-dynamic'`
// without needing `'unsafe-inline'`. The HTML template carries no
// `<script>…</script>` body any more — only `<script src="…"></script>`
// references to `/vendor/swagger-ui/*`, which `'self'` already allows.
//
// L14-01 — two specs are exposed: the legacy hand-maintained
// /openapi.json (v0 surface) and the generated /openapi-v1.json (v1
// contract — single source of truth via Zod schemas). The dropdown
// lets API consumers switch between them; v1 is loaded by default.
window.addEventListener("load", function () {
  window.ui = SwaggerUIBundle({
    urls: [
      { name: "v1 (generated)", url: "/openapi-v1.json" },
      { name: "v0 (legacy)", url: "/openapi.json" },
    ],
    "urls.primaryName": "v1 (generated)",
    dom_id: "#swagger-ui",
    deepLinking: true,
    presets: [
      SwaggerUIBundle.presets.apis,
      SwaggerUIStandalonePreset,
    ],
    plugins: [SwaggerUIBundle.plugins.DownloadUrl],
    layout: "StandaloneLayout",
    persistAuthorization: true,
    displayRequestDuration: true,
    filter: true,
    tryItOutEnabled: true,
  });
});
