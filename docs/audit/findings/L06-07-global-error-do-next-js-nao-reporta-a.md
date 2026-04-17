---
id: L06-07
audit_ref: "6.7"
lens: 6
title: "Global error do Next.js não reporta a Sentry"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "observability"]
files:
  - portal/src/app/global-error.ts
correction_type: process
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
# [L06-07] Global error do Next.js não reporta a Sentry
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/global-error.tsx:1-53` é um Client Component mas **nunca chama** `Sentry.captureException(error)`. Recomendação Sentry+Next oficial é:

```typescript
'use client';
import * as Sentry from '@sentry/nextjs';
import { useEffect } from 'react';

export default function GlobalError({ error, reset }) {
  useEffect(() => { Sentry.captureException(error); }, [error]);
  return <html>...</html>;
}
```
## Risco / Impacto

— Erro fatal na root layout (ex.: `createClient` falhando) é mostrado ao usuário mas **nunca chega ao Sentry** → time de SRE acredita "está tudo bem", usuários silenciosamente frustrados.

## Correção proposta

— Aplicar snippet acima. Mesmo para `portal/src/app/(portal)/error.tsx`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.7).