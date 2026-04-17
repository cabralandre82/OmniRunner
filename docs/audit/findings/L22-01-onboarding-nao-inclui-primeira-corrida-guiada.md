---
id: L22-01
audit_ref: "22.1"
lens: 22
title: "Onboarding não inclui \"primeira corrida guiada\""
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "personas", "athlete-amateur"]
files: []
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
# [L22-01] Onboarding não inclui "primeira corrida guiada"
> **Lente:** 22 — Atleta Amador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Tela `today_screen.dart` e `athlete_dashboard_screen.dart` não têm flow "bem-vindo, vamos fazer sua primeira corrida de 20 min em Z2" com tutorial in-app.
## Risco / Impacto

— Amador baixa app, não sabe o que fazer, deleta. D1 retention baixíssima. **Churn que mata o negócio**.

## Correção proposta

— "Primeira corrida guiada": áudio TTS ("Você está no ritmo certo"), feedback visual simples, parabenização ao final, desbloqueio de badge.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.1).