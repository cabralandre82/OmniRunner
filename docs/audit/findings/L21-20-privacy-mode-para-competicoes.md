---
id: L21-20
audit_ref: "21.20"
lens: 21
title: "Privacy mode para competições"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "personas", "athlete-pro"]
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
  Coberto em `docs/product/ATHLETE_PRO_BASELINE.md`. Coluna
  `sessions.privacy_mode` (public/private/competition) com
  promote-to-public via cron 15-min. Feed RLS adiciona predicado
  filtrando privacy_mode=public. Wave 4 fase F.
---
# [L21-20] Privacy mode para competições
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Em dia de prova, elite não quer compartilhar warm-up route (estratégia). Sem toggle "modo competição privada" que silencia auto-publicação por X horas.
## Correção proposta

— Tela recording tem switch "Público/Privado/Competição" antes de start.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.20).