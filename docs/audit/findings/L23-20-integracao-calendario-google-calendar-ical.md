---
id: L23-20
audit_ref: "23.20"
lens: 23
title: "Integração calendário (Google Calendar / iCal)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["personas", "coach", "integrations", "calendar"]
files:
  - docs/product/COACH_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "k12-pending"

owner: product+backend
runbook: docs/product/COACH_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/COACH_BASELINE.md` § 6
  (iCal calendar feed). Feed read-only (iCalendar RFC
  5545) via `GET /api/athletes/{user_id}/calendar.ics
  ?token={hmac}` — não two-way-sync (Google OAuth fica
  pra Wave 6+ se houver demanda). Token long-lived
  HMAC em `calendar_feed_tokens` (tabela nova), com
  revoke e regenerate. Conteúdo: `plan_workouts`
  próximos 180d + `race_participations` + sessions
  grupo; cada VEVENT com UID estável para overwrite.
  `Cache-Control: private, max-age=900`. Lib
  `ical-generator` npm. Ship Wave 4 fase W4-P
  (independente do resto do K12).
---
# [L23-20] Integração calendário (Google Calendar / iCal)
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Treino agendado não aparece no Google Calendar do atleta/coach.
## Correção proposta

— `GET /api/athletes/:id/calendar.ics` — feed iCal subscribable. Atleta adiciona URL no Google Cal → treinos aparecem automaticamente.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.20).
- `2026-04-24` — Consolidado em `docs/product/COACH_BASELINE.md` § 6 (batch K12); implementação Wave 4 fase W4-P.
