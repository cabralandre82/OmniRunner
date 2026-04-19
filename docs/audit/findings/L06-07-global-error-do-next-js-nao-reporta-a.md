---
id: L06-07
audit_ref: "6.7"
lens: 6
title: "Global error do Next.js não reporta a Sentry"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "observability", "sentry", "error-boundary"]
files:
  - portal/src/lib/observability/reportClientError.ts
  - portal/src/app/global-error.tsx
  - portal/src/app/error.tsx
  - portal/src/app/(portal)/error.tsx
  - portal/src/app/platform/error.tsx
correction_type: process
test_required: true
tests:
  - portal/src/lib/observability/reportClientError.test.ts
  - portal/src/app/global-error.test.tsx
  - portal/src/app/error.test.tsx
  - portal/src/app/(portal)/error.test.tsx
  - portal/src/app/platform/error.test.tsx
linked_issues: []
linked_prs:
  - 5b79094
owner: portal-platform
runbook: docs/observability/ALERT_POLICY.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido criando um único funil `lib/observability/reportClientError.ts`
  que toda fronteira de erro do App Router agora chama dentro de
  `useEffect`. Antes do fix:

  - `app/global-error.tsx` — renderizava o documento raiz mas **nunca**
    importava `@sentry/nextjs`. Crash catastrófico → SRE não sabia que
    o portal estava quebrado.
  - `app/error.tsx` — apenas `console.error`, sem Sentry.
  - `app/(portal)/error.tsx` — sem logging algum.
  - `app/platform/error.tsx` — chamava `Sentry.captureException` direto,
    porém **sem tags**, então não era roteável pelas regras de alerta
    de severidade (L20-05).

  O helper centralizado:

  1. Atribui tag `error_boundary` (`global` | `root` | `portal` |
     `platform`) — permite filtros precisos em Sentry tipo
     "todas as quebras do platform admin na última hora".
  2. Atribui tag `severity` (P1/P2) alinhada com
     `docs/observability/ALERT_POLICY.md`. `global` e `root` são P1
     (paginam on-call); `portal` e `platform` são P2 (Slack apenas).
  3. Preserva `error.digest` como tag — único correlator entre o crash
     do client e a linha de log do RSC server-side que produziu a falha.
  4. Encapsula tudo em `Sentry.withScope` para evitar vazamento de tags
     entre eventos não relacionados.
  5. Tem fail-safe: se a API do Sentry explodir (ex.: extensão do
     navegador bloqueou o bundle), o boundary continua funcionando.
  6. Sempre faz `console.error` no client para que dev local sem DSN
     ainda enxergue o crash.

  Cada `error.tsx` agora também surfaca `error.digest` para o usuário
  (campo `Ref:` monoespaçado) — para que ele possa citar ao suporte
  sem precisarmos pedir que abra DevTools.

  Cobertura de teste: 25 cases novos (helper + 4 boundaries) cobrindo
  estabilidade de tags, propagação do digest, botão "Tentar novamente",
  e os fail-safes de observabilidade.
---
# [L06-07] Global error do Next.js não reporta a Sentry
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed (2026-04-17)
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
- `2026-04-17` — **Fixed** (`5b79094`): central `reportClientError` helper +
  4 boundaries refatoradas, P1/P2 severity routing, `error.digest`
  preservado e exposto ao usuário, 25 novos testes.