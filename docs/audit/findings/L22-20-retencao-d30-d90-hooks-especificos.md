---
id: L22-20
audit_ref: "22.20"
lens: 22
title: "Retenção D30/D90 — hooks específicos"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["mobile", "cron", "personas", "athlete-amateur", "retention"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "k12-pending"

owner: product+backend
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`
  § 11 (D30/D90/D180/D365 retention hooks). Nova fase 9
  em `lifecycle-cron` dispara notificação única na
  marca de cada milestone, com wrapped-lite deep-link
  para `wrapped_screen.dart` (já existe) parametrizado
  por período-desde-signup. Tabela de idempotência
  `retention_hooks_sent` (PK user_id + milestone_day).
  Canais escalam: push+in-app (D30/D90) → +email
  (D180/D365). D180/D365 reusam Wrapped PDF (L22-15).
  Respeita quiet hours / opt-out de push existentes.
  Ship Wave 4 fase W4-N (menor footprint infra).
---
# [L22-20] Retenção D30/D90 — hooks específicos
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Streak + badges cobrem D7. Falta motivador D30+: "aniversário de 1 mês no app", "sua evolução" comparativa.
## Correção proposta

— `lifecycle-cron` dispara notificação especial em D30/D90/D180/D365 com wrapped-lite.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.20).
- `2026-04-24` — Consolidado em `docs/product/ATHLETE_AMATEUR_BASELINE.md` § 11 (batch K12); implementação Wave 4 fase W4-N.
