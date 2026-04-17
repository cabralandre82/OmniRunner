---
id: L15-01
audit_ref: "15.1"
lens: 15
title: "Zero UTM tracking no produto"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["rls", "portal", "migration"]
files:
  - portal/src/lib/attribution.ts
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
# [L15-01] Zero UTM tracking no produto
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep "utm_source|utm_medium" portal/src omni_runner/lib` → **0 matches**. Campanhas de marketing não podem atribuir conversões.
## Risco / Impacto

— CMO gasta R$ 50k em Google Ads → não consegue saber se CAC é R$ 10 ou R$ 500. Decisões de budget no escuro.

## Correção proposta

—

```typescript
// portal/src/lib/attribution.ts
export function captureUtmFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const utm = ["source","medium","campaign","term","content"].reduce((acc, k) => {
    const v = params.get(`utm_${k}`);
    if (v) acc[k] = v;
    return acc;
  }, {} as Record<string, string>);
  if (Object.keys(utm).length) {
    document.cookie = `utm=${btoa(JSON.stringify({...utm, t: Date.now()}))}; path=/; max-age=${90*86400}`;
  }
}

// On signup, attach utm cookie to profile
```

```sql
ALTER TABLE profiles ADD COLUMN attribution jsonb;
-- Examples: {"source":"google","medium":"cpc","campaign":"brand","landing":"/","first_seen_at":"2026-04-15"}
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.1).