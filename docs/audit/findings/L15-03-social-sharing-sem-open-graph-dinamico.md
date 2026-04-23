---
id: L15-03
audit_ref: "15.3"
lens: 15
title: "Social sharing sem Open Graph dinâmico"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/lib/og-metadata.ts
  - portal/src/lib/og-metadata.test.ts
  - portal/src/app/challenge/[id]/opengraph-image.tsx
  - portal/src/app/invite/[code]/opengraph-image.tsx
  - portal/src/app/challenge/[id]/page.tsx
  - portal/src/app/invite/[code]/page.tsx
  - tools/audit/check-og-metadata.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/og-metadata.test.ts
linked_issues: []
linked_prs:
  - local:1b226e0
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Dynamic Open Graph + Twitter metadata now drives every
  shareable portal page. The app no longer records runs
  (Strava is the single source), so the shareable surface is
  the Next.js portal (`/challenge/[id]`, `/invite/[code]`).
  - `portal/src/lib/og-metadata.ts` centralises the Metadata
    contract: `getSiteBaseUrl()` resolves from
    `NEXT_PUBLIC_PORTAL_BASE_URL` / `PORTAL_BASE_URL`
    (rejects non-http), strips trailing slash, defaults to
    `https://omnirunner.app`. `buildOgMetadata({ path, title,
    description, imageUrl? })` emits
    `openGraph.{title,description,url,type,siteName,locale,
    images:[1200x630]}`, `twitter.card=summary_large_image`,
    and `alternates.canonical`. Default image URL is
    `<url>/opengraph-image` — the deterministic path Next.js
    App Router uses for co-located segments.
  - `portal/src/lib/og-metadata.test.ts` (8 vitest cases)
    covers env fallback, env override + trailing-slash
    normalisation, malformed-env rejection, full payload
    shape, image-URL override, and path leading-slash
    normalisation.
  - `portal/src/app/challenge/[id]/opengraph-image.tsx` and
    `portal/src/app/invite/[code]/opengraph-image.tsx` emit
    edge-runtime `ImageResponse` previews with
    `OG_IMAGE_THEMES` palettes + brand lockup.
  - Both `page.tsx` now call `generateMetadata` →
    `buildOgMetadata` with entity-derived title/description
    (short ID / short code). No more ad-hoc `openGraph`
    copies per route.
  - CI guard `npm run audit:og-metadata` asserts 35
    invariants (helper shape, test coverage, OG image routes,
    page wiring).
---
# [L15-03] Social sharing sem Open Graph dinâmico
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep 'og:image' portal/src` → minimo. Corrida compartilhada no WhatsApp/Instagram gera preview genérico.
## Correção proposta

— Next.js App Router: `generateMetadata` por página + endpoint OG image dinâmico:

```typescript
// /app/run/[id]/opengraph-image.tsx
import { ImageResponse } from 'next/og';
export default async function Image({ params }) {
  const run = await fetchRun(params.id);
  return new ImageResponse(<div>{run.distance_km} km em {run.pace}</div>);
}
```

Viralização natural quando atleta compartilha corrida.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.3).