---
id: L16-05
audit_ref: "16.5"
lens: 16
title: "Integrações de marcas esportivas sem schema"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "migration"]
files:
  - supabase/migrations/20260421620000_l16_05_sponsorships.sql
  - supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql
  - tools/audit/check-sponsorships.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-sponsorships.ts
linked_issues: []
linked_prs:
  - "local:725159d"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Brand / sponsorship schema lives server-side. OmniCoin policy
  (L22-02): **desafios são o único fluxo que emite OmniCoins** —
  patrocínios entregam valor via descontos em reais, benefícios
  físicos, exposição de marca, etc., jamais via moeda virtual.

  - `public.brands` catálogo canônico: slug/display_name/URLs com
    CHECK, unique slug, RLS com public-read das `active = true` para
    o mobile renderizar logos.
  - Tabelas ativas: `sponsorships` (contrato por grupo) +
    `sponsorship_athletes` (opt-in atleta-por-atleta).
  - `public.sponsorships` captura contratos por grupo:
    `(group_id, brand_id)`, state machine
    (draft → active → paused → ended/cancelled), CHECK
    `contract_end > contract_start`, CHECK `equipment_discount_pct
    BETWEEN 0 AND 90`, `active_requires_approval`, partial UNIQUE
    `(group_id, brand_id)` enquanto status ∈ {draft, active, paused}.
    As colunas de orçamento em coins (`monthly_coins_per_athlete`,
    `coin_budget_total`, `coin_budget_used`) foram dropadas pela
    migration compensatória de L22-02.
  - `public.sponsorship_athletes` é o join LGPD-safe opt-in (sem
    auto-enrollment — atleta precisa consentir).
  - RPCs: `fn_sponsorship_activate` (platform-admin-or-service-role,
    gate em CONTRACT_EXPIRED + INVALID_TRANSITION),
    `fn_sponsorship_enroll_athlete` (authenticated self, idempotente
    via ON CONFLICT), `fn_sponsorship_opt_out_athlete` (self).
    `fn_sponsorship_distribute_monthly_coins` foi **dropada** pela
    migration compensatória — sponsorship não paga OmniCoins.
  - Reason `sponsorship_payout` (e cinco outros reasons aspiracionais
    que L16-05 havia adicionado — `referral_bonus`, `referral_new_user`,
    `redemption_payout`, `custody_reversal`, `championship_reward`)
    foram **removidos** do `coin_ledger_reason_check` pela compensatória
    L22-02; institution_token_* reasons pré-existentes foram
    reinstalados (L16-05 havia dropado silenciosamente).
  - Invariants bloqueadas por `npm run audit:sponsorships`, que agora
    exige tanto a migration L16-05 quanto a compensatória L22-02.
---
# [L16-05] Integrações de marcas esportivas sem schema
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Nike, Asics, Mizuno patrocinam atletas — produto não tem `sponsorships` table nem `team_equipment_recommendations`.
## Correção proposta

—

```sql
CREATE TABLE public.sponsorships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES coaching_groups(id),
  brand text NOT NULL,
  contract_start date,
  contract_end date,
  equipment_discount_pct numeric(4,1),
  partner_api_key_id uuid REFERENCES api_keys(id)
);
```

> Observação: a proposta original incluía `monthly_coins_to_athletes`.
> Depois da reafirmação da política do produto ("OmniCoins são usadas
> SOMENTE em desafios") esse campo foi deliberadamente excluído e a
> distribuição mensal de coins foi removida do schema — o valor do
> patrocínio flui via desconto em reais e benefícios físicos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.5).
- `2026-04-21` — Entregue schema + RPCs + guard (J29).
- `2026-04-21` — Coin-payout mensal removido após reafirmação da política OmniCoin-challenge-only (L22-02 correction).
