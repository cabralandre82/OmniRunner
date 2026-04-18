---
id: L20-04
audit_ref: "20.4"
lens: 20
title: "Sentry sem tracesSampleRate tuning documentado"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "observability", "reliability"]
files:
  - portal/src/lib/observability/sentryTuning.ts
  - portal/src/lib/observability/sentryTuning.test.ts
  - portal/sentry.client.config.ts
  - portal/sentry.server.config.ts
  - portal/sentry.edge.config.ts
correction_type: config
test_required: true
tests:
  - portal/src/lib/observability/sentryTuning.test.ts
linked_issues: []
linked_prs:
  - "commit:75e4a7f"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "tracesSampler adaptativo (P1=1.0, P2=0.5, P3=0.1, P4=0.0) compartilhado pelos 3 runtimes (client/server/edge) via portal/src/lib/observability/sentryTuning.ts. Honra parentSampled para não quebrar trace contiguity. Calibração documentada em comments + 20 testes unitários."
---
# [L20-04] Sentry sem tracesSampleRate tuning documentado
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** observabilidade
**Personas impactadas:** Plataforma (SRE), DevOps

## Achado
Configs Sentry usavam flat `tracesSampleRate: 0.1` em todos os 3 runtimes
(client, server, edge). Isso significa:
- 10% de TODAS as transações eram amostradas, incluindo `/api/health`
  (que roda a cada 30s — ~28 800 req/dia → 2 880 transações/dia
  desperdiçadas em quota Sentry).
- 10% das transações de `/api/custody/withdraw` (rota P1) eram coletadas
  — em incidente de pagamento, 90% dos traces necessários para
  forensics estão faltando.

## Risco / Impacto
- **Forense impossível em P1**: "este saque demorou 15s — onde foi o
  bottleneck?" Sem trace, tem que adivinhar.
- **Quota desperdiçada**: ~30% da quota Sentry consumida por
  `/api/health`, sem valor de debug.
- **Custo crescente sem governance**: dobrar usuários → dobrar quota.
  Sem sampler adaptativo, o team acaba reduzindo TUDO para 1% num
  cost-cutting reativo, perdendo visibilidade onde mais importa.

## Correção implementada

Módulo central `portal/src/lib/observability/sentryTuning.ts`:

### `tracesSampler` adaptativo
```typescript
const SAMPLE_RATES = {
  P1: 1.0,    // money/security/auth — full forensic visibility
  P2: 0.5,    // critical user paths — high but budget-aware
  P3: 0.1,    // default — statistically meaningful for p99
  P4: 0.0,    // health/static/monitoring — pure noise
};
```

### Honra `parentSampled`
Quando upstream sinaliza decisão de amostragem (e.g. mobile envia
`sentry-trace` header), seguimos para evitar trace tree quebrado.

### Compartilhado pelos 3 runtimes
`sentry.client.config.ts`, `sentry.server.config.ts`,
`sentry.edge.config.ts` importam de `sentryTuning.ts` (single source of
truth). Sem drift entre runtimes.

### Testes
20 testes unitários em `sentryTuning.test.ts` cobrindo:
- Classificação de severidade por rota (P1/P2/P3/P4 + default + edge cases)
- Sample rate por path
- `tracesSampler` honrando parent decision
- Fallback quando context é vazio

## Calibração

| Severidade | Sample rate | Justificativa |
|---|---|---|
| P1 (custody/swap/auth/billing) | 100% | Cada trace = potencial forensic em incidente financeiro |
| P2 (sessions/coaching/runs) | 50% | Suficiente para p99, deixa budget para P1 |
| P3 (default) | 10% | Statistically meaningful (Sentry recommendation) |
| P4 (health/liveness/static) | 0% | Pura monitoração — não consome quota |

Modificar requer PR com cost-impact analysis comentado.

## Teste de regressão
- `cd portal && npx vitest run src/lib/observability/sentryTuning.test.ts`
- 20 testes passando
- TypeScript strict mode validado (`npx tsc --noEmit` ✅)

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.4]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.4).
- `2026-04-17` — Correção implementada: módulo central `sentryTuning.ts` com sampler adaptativo P1/P2/P3/P4 + 20 testes unitários. Compartilhado pelos 3 runtimes Sentry. Promovido a `fixed`.
