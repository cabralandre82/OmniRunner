---
id: L15-03
audit_ref: "15.3"
lens: 15
title: "Social sharing sem Open Graph dinâmico"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files: []
correction_type: code
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L15-03] Social sharing sem Open Graph dinâmico
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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