---
id: L03-04
audit_ref: "3.4"
lens: 3
title: "1 Coin = US$ 1.00 (peg enforcement)"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["finance", "migration"]
files:
  - supabase/migrations/20260303100000
correction_type: migration
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
# [L03-04] 1 Coin = US$ 1.00 (peg enforcement)
> **Lente:** 3 — CFO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`supabase/migrations/20260303100000:24-26`:
```sql
ALTER TABLE public.custody_deposits
  ADD CONSTRAINT chk_peg_1_to_1
    CHECK (amount_usd = coins_equivalent::numeric);
```
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.4).