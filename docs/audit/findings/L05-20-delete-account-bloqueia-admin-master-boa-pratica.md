---
id: L05-20
audit_ref: "5.20"
lens: 5
title: "delete-account bloqueia admin_master (boa prática)"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: []
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
# [L05-20] delete-account bloqueia admin_master (boa prática)
> **Lente:** 5 — CPO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 46-49 negam auto-exclusão do admin_master.
## Correção proposta

— Nenhuma. Pode-se melhorar com "há 2 admin_master? ok; só 1? bloqueie com mensagem explicativa".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.20).