import { NextResponse } from "next/server";

/**
 * GET /api/docs
 *
 * Serves Swagger UI HTML page for the Omni Runner Portal API documentation.
 *
 * L14-03 (supply chain): assets de Swagger-UI são self-hosted em
 * `/vendor/swagger-ui/*` — copiados de `node_modules/swagger-ui-dist` via
 * `scripts/copy-swagger-ui.mjs` (roda em `prebuild`, `predev`, `postinstall`).
 * Elimina a dependência de unpkg/CDN e remove o risco de RCE em admin
 * autenticado caso o CDN seja comprometido.
 *
 * Política de cache (Cache-Control: no-store) aplicada ao HTML para que
 * atualizações no openapi.json e nos assets sejam observadas imediatamente.
 * Os assets em /vendor/swagger-ui/* são servidos pelo Next com cache longo
 * (controlado via headers globais, não-inline aqui).
 */
export async function GET() {
  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Omni Runner Portal API - Documentação</title>
  <link rel="icon" type="image/png" sizes="32x32" href="/vendor/swagger-ui/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="/vendor/swagger-ui/favicon-16x16.png">
  <link rel="stylesheet" href="/vendor/swagger-ui/swagger-ui.css">
  <style>
    :root {
      --omni-primary: #2563eb;
      --omni-dark: #0f172a;
    }
    .swagger-ui .topbar { background: var(--omni-dark) !important; }
    .swagger-ui .info .title { color: var(--omni-primary); }
    body { margin: 0; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="/vendor/swagger-ui/swagger-ui-bundle.js"></script>
  <script src="/vendor/swagger-ui/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = function() {
      window.ui = SwaggerUIBundle({
        // L14-01 — two specs are exposed: the legacy hand-maintained
        // /openapi.json (v0 surface) and the generated
        // /openapi-v1.json (v1 contract — single source of truth via
        // Zod schemas). The dropdown lets API consumers switch between
        // them; v1 is loaded by default.
        urls: [
          { name: "v1 (generated)", url: "/openapi-v1.json" },
          { name: "v0 (legacy)",    url: "/openapi.json" }
        ],
        "urls.primaryName": "v1 (generated)",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        plugins: [
          SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "StandaloneLayout",
        persistAuthorization: true,
        displayRequestDuration: true,
        filter: true,
        tryItOutEnabled: true
      });
    };
  </script>
</body>
</html>`;

  return new NextResponse(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    },
  });
}
