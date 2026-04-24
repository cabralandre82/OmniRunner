---
id: L04-14
audit_ref: "4.14"
lens: 4
title: "Ausência de verificação de idade (COPPA/ECA)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["lgpd", "rls", "ux", "minors"]
files:
  - docs/policies/MINOR_USER_AGE_VERIFICATION.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 9b5eb71

owner: legal+product
runbook: docs/policies/MINOR_USER_AGE_VERIFICATION.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Política ratificada em
  `docs/policies/MINOR_USER_AGE_VERIFICATION.md`. Modelo
  3-tier: < 13 (sem signup direto, vira `dependent_profiles`
  sob conta dos pais), 13–17 (signup com double-opt-in
  parental por email), 18+ (fluxo padrão). Coleta apenas
  ano de nascimento (LGPD minimisation). Schema + RLS +
  onboarding UI + backfill modal de existing users planejados
  em Wave 3. Política inclui regras operacionais (no leaderboard
  exposure para menores, no Strava/TP OAuth binding,
  hard-delete sem grace period quando consent é revogado, audit
  trail `event_domain='lgpd'`).
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