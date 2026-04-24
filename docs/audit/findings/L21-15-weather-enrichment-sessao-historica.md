---
id: L21-15
audit_ref: "21.15"
lens: 21
title: "Weather enrichment (sessão histórica)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["personas", "athlete-pro"]
files:
  - docs/product/ATHLETE_PRO_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product+platform
runbook: docs/product/ATHLETE_PRO_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_PRO_BASELINE.md` (umbrella
  Atleta-Pro). Decisão: backfill via cron `enrich-weather` (4h)
  usando OpenWeather One Call v3 com Open-Meteo como fallback
  free-tier. Coluna `sessions.weather jsonb` com cap de 1k
  calls/dia. Wave 4 fase A.
---
# [L21-15] Weather enrichment (sessão histórica)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Pace no calor ≠ pace no frio; não há temperatura registrada por sessão.
## Correção proposta

— Pós-processamento via OpenWeather API; armazenar `sessions.weather jsonb`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.15).