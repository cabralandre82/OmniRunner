---
id: L20-04
audit_ref: "20.4"
lens: 20
title: "Sentry sem tracesSampleRate tuning documentado"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "observability", "reliability"]
files: []
correction_type: config
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
# [L20-04] Sentry sem tracesSampleRate tuning documentado
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Configs Sentry não auditadas aqui, mas padrão SDK costuma ser `tracesSampleRate: 1.0` (tudo) em dev e undefined em prod.
## Correção proposta

— Sample adaptativo:

```typescript
Sentry.init({
  dsn, tracesSampler: (samplingContext) => {
    if (samplingContext.name?.includes("/api/health")) return 0.0;
    if (samplingContext.name?.includes("/api/custody") ||
        samplingContext.name?.includes("/api/swap")) return 1.0;
    return 0.1;
  },
});
```

Custódia/swap = 100% trace; resto 10%.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.4).