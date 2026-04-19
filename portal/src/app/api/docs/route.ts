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
 * L01-38: o bootstrap do Swagger-UI vivia inline neste handler num
 * `<script>…</script>`, o que forçava `script-src 'unsafe-inline'` no
 * CSP da rota inteira (e por extensão, do portal). Migrado para
 * `/vendor/swagger-ui/swagger-init.js` — a referência cabe sob
 * `script-src 'self'` e nada mais precisa de relaxamento. O `<style>`
 * inline permanece (CSP `style-src 'self' 'unsafe-inline'`, decisão
 * documentada em `lib/security/csp.ts`).
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
  <script src="/vendor/swagger-ui/swagger-init.js"></script>
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
