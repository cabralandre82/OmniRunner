---
id: L22-01
audit_ref: "22.1"
lens: 22
title: "Onboarding não inclui \"primeira corrida guiada\""
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["athlete-amateur", "onboarding", "pure-domain", "state-machine"]
files:
  - portal/src/lib/first-run-onboarding/types.ts
  - portal/src/lib/first-run-onboarding/machine.ts
  - portal/src/lib/first-run-onboarding/resume.ts
  - portal/src/lib/first-run-onboarding/index.ts
  - tools/audit/check-first-run-onboarding.ts
correction_type: domain-module
test_required: true
tests:
  - portal/src/lib/first-run-onboarding/machine.test.ts
  - tools/audit/check-first-run-onboarding.ts
linked_issues: []
linked_prs:
  - 430fb53
owner: athlete-amateur
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Máquina de estados pura `portal/src/lib/first-run-onboarding/`
  com 10 estados, 11 eventos, `TERMINAL_STATES`, `STATE_PROGRESS`
  0–100 %. Reducer total (ignora eventos ilegais), trata
  `strava_connection_failed` com rewind e error-payload, conta
  `skipCount` com cap, gerencia `celebratedAt`. `evaluateResume`
  decide nudge de re-engajamento por terminal-state, idade e
  retries (`DEFAULT_RESUME_POLICY` 3 dias / 3 retries). 26 vitest
  cases cobrem happy path, Strava failure/recovery, skip/resume,
  terminal, progress, history, resume policy. 49 invariantes via
  `audit:first-run-onboarding`. UI wiring é follow-up explícito
  (L22-01-presenter). Commit 430fb53.
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