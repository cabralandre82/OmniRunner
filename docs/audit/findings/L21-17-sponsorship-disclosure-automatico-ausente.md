---
id: L21-17
audit_ref: "21.17"
lens: 21
title: "Sponsorship disclosure automático ausente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration", "personas", "athlete-pro"]
files:
  - docs/product/ATHLETE_PRO_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - b2007d6

owner: product+legal
runbook: docs/product/ATHLETE_PRO_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_PRO_BASELINE.md`. Tabela
  `sponsorships` + auto-checkbox 'Post patrocinado' em compose
  post (default ON, audit-logged se desmarcado). Compliance:
  Brasil Lei 13.146 + CONAR / EUA FTC 16 CFR Part 255. Wave 4
  fase C.
---
# [L21-17] Sponsorship disclosure automático ausente
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Em rede social integrada (feed), posts de elite patrocinado não indicam "#Patrocinado" — lei federal dos EUA FTC + Lei 13.146 Brasil exigem.
## Correção proposta

— Atleta com `sponsorships` ativa vê checkbox "Post patrocinado" auto-marcado.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.17).