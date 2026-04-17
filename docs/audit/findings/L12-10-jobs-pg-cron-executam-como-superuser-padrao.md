---
id: L12-10
audit_ref: "12.10"
lens: 12
title: "Jobs pg_cron executam como superuser (padrão)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["cron"]
files: []
correction_type: code
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
# [L12-10] Jobs pg_cron executam como superuser (padrão)
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— pg_cron roda na role do criador da função (`postgres`/`supabase_admin`). Função fallha + roda em role elevada = blast radius grande.
## Correção proposta

— Supabase "Database → Cron" UI permite escolher role. Criar role dedicada `cron_worker` com permissões mínimas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.10).