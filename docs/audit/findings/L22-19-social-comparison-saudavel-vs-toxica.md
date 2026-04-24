---
id: L22-19
audit_ref: "22.19"
lens: 22
title: "Social comparison saudável vs tóxica"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["performance", "personas", "athlete-amateur", "social"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "fce133b"

owner: product+backend+mobile
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`
  § 10 (Healthy social comparison). Feed default
  scopeado: grupo + seguidos + bracket peers (decile de
  pace ±1). Materialized view `athlete_pace_decile`
  (ntile sobre mediana de pace dos últimos 56 dias,
  refresh semanal segunda 03:00 UTC). "Feed global"
  opt-in via `athlete_settings.feed_scope` com sheet
  explicativo. Leaderboards (L21-16, championships) NÃO
  são scopeados — são surfaces competitivas com self-
  selection. Copy nudge no onboarding (L22-18) para
  definir expectativa. Ship Wave 4 fase W4-M (depende
  do cron de decile, owned pelo data platform).
---
# [L22-19] Social comparison saudável vs tóxica
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Feed mostra corrida de todos. Amador iniciante vê elite fazendo sub-40 em 10K → desmotiva.
## Correção proposta

— Feed default = **grupo do atleta** + seguidos. Algoritmo prioriza atletas de bracket similar. Opt-in para "feed global" com aviso "pode incluir performances muito superiores às suas".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.19).
- `2026-04-24` — Consolidado em `docs/product/ATHLETE_AMATEUR_BASELINE.md` § 10 (batch K12); implementação Wave 4 fase W4-M.
