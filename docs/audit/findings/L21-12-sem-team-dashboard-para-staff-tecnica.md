---
id: L21-12
audit_ref: "21.12"
lens: 21
title: "Sem \"team dashboard\" para staff técnica"
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
# [L21-12] Sem "team dashboard" para staff técnica
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach individual vê atleta. Elite tem **equipe**: técnico + fisiologista + fisioterapeuta + nutricionista + psicólogo. Sem roles múltiplos.
## Correção proposta

— `coaching_members.role` ampliar para `['admin_master','coach','assistant','physio','nutritionist','psychologist','athlete']` com permissões granulares em `role_permissions`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.12).