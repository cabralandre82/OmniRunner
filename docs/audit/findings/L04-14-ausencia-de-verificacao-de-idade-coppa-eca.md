---
id: L04-14
audit_ref: "4.14"
lens: 4
title: "Ausência de verificação de idade (COPPA/ECA)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "ux"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-14] Ausência de verificação de idade (COPPA/ECA)
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Omni Runner não coleta `date_of_birth`. Menores de 13 anos (COPPA) e de 12 anos (ECA) não podem ser titulares diretos. Corridas de categoria infantil existem → pode atrair < 13 anos.
## Risco / Impacto

— FTC COPPA, ANPD minors policy.

## Correção proposta

— Onboarding pergunta ano de nascimento; se < 18 → fluxo de consentimento parental (email do responsável + verificação dupla).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.14).