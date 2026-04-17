---
id: L13-02
audit_ref: "13.2"
lens: 13
title: "Nome da constante ainda em português (ADMIN_PROFESSOR_ROUTES)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "migration"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L13-02] Nome da constante ainda em português (ADMIN_PROFESSOR_ROUTES)
> **Lente:** 13 — Middleware · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha 23 ainda usa `PROFESSOR`, apesar da migration `20260304050000_fix_coaching_role_mismatch.sql` renomear role `professor → coach`. É inconsistência que revela que a migração não foi propagada ao código TypeScript.
## Risco / Impacto

— Dev novo vai procurar `ADMIN_COACH_ROUTES`, não encontra, implementa errado. Sintoma de **debt semântico** generalizado (verificar outros lugares).

## Correção proposta

— Rename + grep do repo inteiro:

```bash
rg -l "professor|assessoria|assistente" portal/src omni_runner/lib supabase
```

Mapear legacy Portuguese → English consistently.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.2).