---
id: L21-08
audit_ref: "21.8"
lens: 21
title: "Lap splits manuais inexistentes em tela de corrida"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["personas", "athlete-pro"]
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
note: null
---
# [L21-08] Lap splits manuais inexistentes em tela de corrida
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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