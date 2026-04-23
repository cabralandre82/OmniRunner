---
id: L15-01
audit_ref: "15.1"
lens: 15
title: "Zero UTM tracking no produto"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["rls", "portal", "migration"]
files:
  - portal/src/lib/attribution.ts
  - portal/src/app/api/attribution/capture/route.ts
  - supabase/migrations/20260421520000_l15_01_utm_attribution.sql
  - tools/audit/check-utm-attribution.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:f6fd338
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Full UTM capture pipeline: client cookie (first-touch, 90-day
  TTL, marketing-consent gated, length-clamped) → POST
  /api/attribution/capture (zod-validated, rate-limited, IP
  truncated to /24 or /48, UA sha256-hashed) →
  marketing_attribution_events (append-only, CHECK on identity
  and per-field length, RLS for own-user + platform_admin) →
  SECURITY DEFINER AFTER INSERT trigger that snapshots first-
  touch into profiles.attribution (jsonb). Events registered at
  180-day retention in audit_logs_retention_config. Ships with
  audit:utm-attribution guard (37 invariants).
---
# [L15-01] Zero UTM tracking no produto
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
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