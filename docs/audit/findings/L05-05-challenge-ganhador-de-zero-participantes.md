---
id: L05-05
audit_ref: "5.5"
lens: 5
title: "Challenge: ganhador de zero participantes"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["challenge", "sql", "rpc", "atomic", "settlement"]
files:
  - supabase/migrations/20260421470000_l05_05_zero_winner_challenge_settlement.sql
  - tools/audit/check-zero-participant-settle.ts
correction_type: rpc
test_required: true
tests:
  - tools/audit/check-zero-participant-settle.ts
linked_issues: []
linked_prs:
  - 29098d7
owner: challenges
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  RPC atômica `fn_settle_zero_winner_challenge` (SECURITY DEFINER,
  search_path pinned) detecta challenges sem participantes elegíveis e
  retorna o stake aos depositantes via reverse_burn helpers em vez de
  premiar um "ganhador fantasma". Migration 20260421470000 + commit
  29098d7. Reconciliação de wallets validada por self-test.
---
# [L05-05] Challenge: ganhador de zero participantes
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Se challenge `start` mas nenhum participante cumpre o objetivo, `settle-challenge` distribui prêmio para ninguém. Prêmio em `token_inventory` do host desapareceu do `total_committed` → precisa ser devolvido.
## Risco / Impacto

— Perda de inventário (2–5 % anual se 10 % dos challenges ficam vazios).

## Correção proposta

— `settle-challenge` verifica `participants_completed == 0` → chama `custody_release_committed` e marca challenge `expired_no_winners`.

## Teste de regressão

— `challenge_no_winners.test.ts`: criar challenge, ninguém completa → após `settle`, `total_committed` volta ao nível anterior.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.5).