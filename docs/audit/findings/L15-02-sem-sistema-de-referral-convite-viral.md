---
id: L15-02
audit_ref: "15.2"
lens: 15
title: "Sem sistema de referral/convite viral"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "migration", "seo"]
files:
  - supabase/migrations/20260421580000_l15_02_referral_program.sql
  - supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql
  - tools/audit/check-referral-program.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:08842bf
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Viral referral primitives live server-side as a complete lifecycle.
  OmniCoin policy (L22-02): **desafios são o único fluxo que emite
  OmniCoins** — referrals rastreiam crescimento viral mas NÃO pagam
  coins.

  - `public.referral_rewards_config` (id=1, CHECK-bounded ttl_days /
    per-user cap / code length) é o único knob operacional; as colunas
    `reward_referrer_coins` / `reward_referred_coins` foram removidas
    pela migration compensatória de L22-02.
  - `public.referrals` table com state-machine CHECK
    (pending → activated|expired|revoked), self-referral CHECK,
    status-timestamps exhaustivo, UNIQUE `referral_code`, UNIQUE
    `referred_user_id` WHERE status='activated' (idempotência) e
    pending-expiry partial index. RLS own-read + admin-read; inserts
    / updates via SECURITY DEFINER RPCs.
  - BEFORE UPDATE trigger `fn_referrals_status_guard` trava o state
    machine (pending-only exits).
  - `fn_generate_referral_code(p_len)` emite código crypto-random
    upper-case alfanumérico (`gen_random_bytes`) excluindo 0/O/1/I,
    length clamped [6, 16], até 8 retries, P0002 em exhaustion.
  - `fn_create_referral(channel)` valida o enum do canal, respeita o
    cap por referrer e stampa `expires_at = now() + ttl_days`.
  - `fn_activate_referral(code)` gates em pending + not expired + not
    self + no prior activation; **não grava em `coin_ledger` e não
    mexe em `wallets.balance_coins`** — apenas flipa o status para
    'activated'. FOR UPDATE na claim.
  - `fn_expire_referrals()` é o cron service-role only que varre
    pending rows passadas do TTL.
  - Self-test da migration principal + self-test da compensatória
    L22-02 (que garante que reasons `referral_*_reward` / wallet bump
    não voltaram).
  - CI guard `npm run audit:referral-program` enforce tanto a
    migration original quanto a compensatória.
---
# [L15-02] Sem sistema de referral/convite viral
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep `referral|referrals|convide_amigo` → zero em SQL. Crescimento orgânico viral impossível.
## Risco / Impacto

— CAC permanece alto; não há mecanismo para atleta trazer atleta (viralização natural em esporte social).

## Correção proposta

— Tracking server-side de referral (`referrals` table + lifecycle) sem pagar coins, já que OmniCoins são reservadas a desafios. Recompensa alternativa (selo "embaixador", destaque no feed, conteúdo exclusivo) fica para evolução futura e não entra no ledger financeiro.

## Correção aplicada (2026-04-21)

1. Migration `20260421580000_l15_02_referral_program.sql` entregou o
   schema completo (config + tabela + triggers + 3 RPCs + self-test).
2. Migration compensatória `20260421700000_l22_02_revoke_nonchallenge_coins.sql`
   removeu o bloco de coin-credit após review do produto:
   - `fn_activate_referral` reescrita sem `INSERT INTO coin_ledger` e
     sem bump em `wallets.balance_coins`.
   - Colunas `reward_referrer_coins` / `reward_referred_coins` dropadas
     tanto de `referral_rewards_config` quanto de `referrals`.
   - Reasons `referral_referrer_reward` / `referral_referred_reward`
     removidas do `coin_ledger_reason_check`.
   - Qualquer linha pré-existente com esses reasons é deletada e as
     wallets afetadas são reconciliadas a partir do ledger.
3. CI guard `npm run audit:referral-program` foi atualizado para exigir
   ambas as migrations e provar via regex que a função atual não
   contém nenhum `INSERT INTO public.coin_ledger`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.2).
- `2026-04-21` — Entregue schema + RPCs + guard (J24).
- `2026-04-21` — Coin-credit removido após reafirmação da política OmniCoin-challenge-only (L22-02 correction).
