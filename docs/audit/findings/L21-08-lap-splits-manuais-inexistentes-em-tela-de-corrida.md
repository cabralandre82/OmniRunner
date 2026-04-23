---
id: L21-08
audit_ref: "21.8"
lens: 21
title: "Lap splits manuais inexistentes em tela de corrida"
severity: high
status: wont-fix
wave: 1
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["personas", "athlete-pro", "strava-only-scope"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  **wont-fix (2026-04-21).** Finding pede botão "Lap"
  físico na tela de recording do app + auto-lap
  configurável. O produto não tem mais tela de recording
  desde a Sprint 25.0.0 (`docs/ARCHITECTURE.md` §7 —
  Strava-only); atletas usam Garmin/Coros no pulso ou o
  Strava app para gravar, e o Omni consome a atividade
  via webhook Strava que já inclui `laps[]` estruturados.
  Exposição dos laps já-capturados pelo Strava na UI do
  Omni é um enhancement de visualização não coberto por
  este finding.
---
# [L21-08] Lap splits manuais inexistentes em tela de corrida
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🚫 wont-fix (Sprint 25.0.0 — Strava-only)
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep "lap\|split_manual\|auto_lap" omni_runner/lib/presentation/screens` → pouco. Tela de recording sem botão "lap" físico.
## Risco / Impacto

— Treino estruturado ("10 × 400 m r/200 m") não consegue ser marcado durante execução. Atleta usa Garmin/Coros no pulso → Omni vira redundante.

## Correção proposta

—

1. Botão "Lap" grande no recording screen com haptic feedback.
2. Auto-lap configurável (1 km, 1 mi, custom distance, por tempo).
3. **Interval mode**: executa sequência "trabalho/descanso" configurada, beep ao trocar.
4. `sessions.laps jsonb` salva splits.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.8).
- `2026-04-21` — **Fechado como `wont-fix`**. Não há tela de recording no app desde Sprint 25.0.0 (`docs/ARCHITECTURE.md` §7); laps vêm estruturados no payload Strava.