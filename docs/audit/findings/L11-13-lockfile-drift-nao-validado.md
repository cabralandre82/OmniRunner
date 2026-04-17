---
id: L11-13
audit_ref: "11.13"
lens: 11
title: "Lockfile drift não validado"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
files: []
correction_type: process
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
# [L11-13] Lockfile drift não validado
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— CI não faz `npm ci --only=production` nem `npm install --frozen-lockfile`. Dev esquece de commitar lockfile atualizado.
## Correção proposta

—

```yaml
- run: npm ci  # falha se lockfile out-of-sync
- run: git diff --exit-code package-lock.json
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.13).