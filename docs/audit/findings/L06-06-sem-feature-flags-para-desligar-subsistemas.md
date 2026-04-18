---
id: L06-06
audit_ref: "6.6"
lens: 6
title: "Sem feature flags para desligar subsistemas"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "migration", "reliability"]
files:
  - "supabase/migrations/20260417250000_feature_flags_kill_switches.sql"
  - "portal/src/lib/feature-flags.ts"
  - "supabase/functions/_shared/feature_flags.ts"
  - "portal/src/app/api/distribute-coins/route.ts"
  - "portal/src/app/api/custody/withdraw/route.ts"
  - "portal/src/app/api/swap/route.ts"
  - "portal/src/app/api/platform/feature-flags/route.ts"
  - "portal/src/app/platform/feature-flags/page.tsx"
  - "portal/src/app/platform/feature-flags/feature-flag-row.tsx"
  - "docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md"
  - "docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md"
correction_type: code
test_required: true
tests:
  - "portal/src/lib/feature-flags.test.ts"
  - "portal/src/app/api/platform/feature-flags/route.test.ts"
linked_issues: []
linked_prs:
  - "commit:HEAD"
owner: unassigned
runbook: docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Implementado kill switch operacional via extensão da tabela
  `feature_flags` existente (criada em 20260304950000). Mudanças:

  **DB layer (`20260417250000_feature_flags_kill_switches.sql`)**
  - ALTER TABLE add: `id` (UUID PK), `scope` (`global`/`group:<uuid>`/...),
    `category` (`product`/`kill_switch`/`banner`/`experimental`/`operational`),
    `reason`, `updated_by`. PK migra para `id`, `(key, scope)` UNIQUE.
  - `feature_flag_audit` table + trigger que captura toda mudança
    (INSERT/UPDATE/DELETE) com OLD vs NEW, actor, role e timestamp.
  - SQL helpers: `fn_feature_resolve(key, scope)`, `fn_feature_enabled`
    (fail-open default), `fn_assert_feature_enabled` (RAISE com SQLSTATE
    `P0F01`).
  - RLS UPDATE/INSERT/DELETE restritos a `profiles.platform_role='admin'`
    OU service_role.
  - Seed: 6 kill switches (`distribute_coins`, `custody.deposits`,
    `custody.withdrawals`, `clearing.interclub`, `swap`, `auto_topup`)
    + 2 banners (`gateway_outage`, `maintenance_mode`).
  - LGPD coverage: `feature_flags.updated_by` e
    `feature_flag_audit.actor_user_id` registrados como
    `defensive_optional` (preserva trilha sem expor PII após deleção).
  - Invariants check inline na migration (smoke test ao aplicar).

  **Portal lib (`portal/src/lib/feature-flags.ts`)**
  - `FeatureDisabledError` (status 503, code `FEATURE_DISABLED`) —
    classe exportada para route handlers.
  - `assertSubsystemEnabled(key, hint?)` — fail-open + throw quando
    flag está OFF. Distinto de `isFeatureEnabled` (legacy, fail-closed
    para product rollouts).
  - `isSubsystemEnabled(key)` — boolean fail-open.
  - `setFeatureFlag({ key, enabled, reason, ... })` — wrapper auditado
    com invalidação automática de cache.
  - `invalidateFeatureCache()` — exposta para tests e route handler.

  **Edge function lib (`supabase/functions/_shared/feature_flags.ts`)**
  - Mirror Deno-compatible: TTL=15s (vs 60s no portal — edges são
    short-lived e devem reagir mais rápido a kill switch).
  - `featureDisabledResponse(err)` helper — Response 503 padronizado
    com `Retry-After: 30`.

  **Wiring nos endpoints críticos** — `assertSubsystemEnabled` no
  start de:
  - `POST /api/distribute-coins` → `distribute_coins.enabled`
  - `POST /api/custody/withdraw` → `custody.withdrawals.enabled`
  - `POST /api/swap` → `swap.enabled`

  Quando OFF, response é `{ error, code: "FEATURE_DISABLED", key }` com
  status 503 e `Retry-After: 30..60`.

  **Admin UI (`/platform/feature-flags`)**
  - Corrigido bug pré-existente: page consultava `id` (não existia) e
    API consultava `platform_admins` (tabela inexistente). Agora usa
    `id` real (post-migration) e `profiles.platform_role='admin'`.
  - Visual: badge por categoria (kill_switch=danger, banner=warning,
    operational=info, product=brand, experimental=neutral).
  - Aviso topo "Estado operacional atípico" lista kill switches OFF e
    banners ON em destaque.
  - Toggle exige campo "Motivo" (mín 3 chars) — vai para
    `feature_flag_audit.reason`. API valida reason.
  - Cache invalida no save → próximo request reflete a mudança.

  **Tests**: 14 unit tests novos em `portal/src/lib/feature-flags.test.ts`
  (cobertura de `assertSubsystemEnabled`, `FeatureDisabledError`,
  fail-open semantics, cache invalidation). Tests existentes de rotas
  financeiras atualizados para mockar `@/lib/feature-flags`. 784/784
  passando, validate-migrations 166/166 + 146/146 integration tests.

  **Runbooks atualizados** — `CUSTODY_INCIDENT_RUNBOOK.md` e
  `GATEWAY_OUTAGE_RUNBOOK.md` reescritos para usar o schema real
  (`enabled boolean + reason + updated_by + audit query`) em vez do
  schema hipotético (`value text + scope text`) que eu havia escrito
  antes. Vercel env var fica como fallback emergency-only.

  Follow-ups conhecidos:
  - Wirear `clearing.interclub.enabled` e `auto_topup.enabled` no
    edge function `settle-clearing` e crons (não há route handler
    correspondente no portal — backlog).
  - Banner público no layout do portal (lê `banner.gateway_outage`)
    ainda não foi instalado — finding novo se priorizado.
  - `scope='group:<uuid>'` suportado no schema mas UI ainda só lista
    scope global; multi-scope toggle via UI fica como follow-up
    (workaround: SQL direto).
---
# [L06-06] Sem feature flags para desligar subsistemas
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Em caso de bug em swap/clearing/custody, a única forma de desligar é deploy. Não há tabela `feature_flags` consultada no início de cada Edge/Route Handler.
## Risco / Impacto

— Bug descoberto 02:00, deploy demora 20 min, perda estimada US$ X/min.

## Correção proposta

—

```sql
CREATE TABLE public.feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT true,
  updated_by uuid,
  updated_at timestamptz DEFAULT now()
);
INSERT INTO feature_flags(key, enabled) VALUES
  ('swap.enabled', true),
  ('custody.deposits.enabled', true),
  ('custody.withdrawals.enabled', true),
  ('clearing.interclub.enabled', true),
  ('distribute_coins.enabled', true),
  ('auto_topup.enabled', true);
```

```typescript
export async function assertFeature(key: string) {
  const { data } = await db.from("feature_flags").select("enabled").eq("key", key).maybeSingle();
  if (!data?.enabled) throw new FeatureDisabledError(key);
}
```

Adicionar no começo de cada endpoint financeiro. UI `/platform/flags` para admin_master toggle imediato.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.6).
- `2026-04-17` — Migration 20260417250000 + lib portal + Deno mirror +
  wiring em 3 routes + admin UI + tests. Status → `fixed`.