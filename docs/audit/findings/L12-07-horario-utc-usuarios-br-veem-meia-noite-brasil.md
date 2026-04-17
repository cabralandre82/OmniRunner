---
id: L12-07
audit_ref: "12.7"
lens: 12
title: "Horário UTC → usuários BR veem \"meia-noite Brasil\""
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "cron", "ux"]
files: []
correction_type: config
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
# [L12-07] Horário UTC → usuários BR veem "meia-noite Brasil"
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `clearing-cron` roda 02:00 UTC = 23:00 BRT. Aceitável. Mas `onboarding-nudge-daily` 10:00 UTC = 07:00 BRT — pode ser cedo demais para notificação push.
## Correção proposta

— Ajustar para 12:00 UTC (09:00 BRT). Ou, melhor: job consulta `profiles.timezone` ([7.6]) e envia push nas "09:00 locais" de cada usuário (exigindo granularidade por timezone).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.7).