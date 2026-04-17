---
id: L07-02
audit_ref: "7.2"
lens: 7
title: "Onboarding não distingue papéis (atleta, coach, admin_master)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "integration", "portal", "ux"]
files:
  - portal/src/components/onboarding/onboarding-overlay.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L07-02] Onboarding não distingue papéis (atleta, coach, admin_master)
> **Lente:** 7 — CXO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/components/onboarding/onboarding-overlay.tsx` tem um único fluxo. Coach amador precisa aprender conceitos "custody, clearing, swap" ao mesmo tempo que vê a UI. Atleta vê a mesma coisa.
## Risco / Impacto

— Churn alto no D1/D7. Especialmente treinadores sem formação financeira se sentem perdidos.

## Correção proposta

— Fluxos diferentes:

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.2).