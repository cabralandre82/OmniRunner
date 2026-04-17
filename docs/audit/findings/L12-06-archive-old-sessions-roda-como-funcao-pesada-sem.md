---
id: L12-06
audit_ref: "12.6"
lens: 12
title: "archive-old-sessions roda como função pesada sem batch"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["atomicity"]
files: []
correction_type: code
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
# [L12-06] archive-old-sessions roda como função pesada sem batch
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `fn_archive_old_sessions()` provavelmente move linhas para partição fria/S3 de uma só vez. Sem `LIMIT` por execução, lock longo de `sessions`.
## Correção proposta

— Loop em batch de 1000 + `COMMIT` entre batches (via function autonomous transactions ou DO block com savepoints).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.6).