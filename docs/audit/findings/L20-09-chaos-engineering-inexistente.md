---
id: L20-09
audit_ref: "20.9"
lens: 20
title: "Chaos engineering inexistente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["rate-limit", "mobile", "edge-function", "testing"]
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
# [L20-09] Chaos engineering inexistente
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Nenhum teste de caos (desligar Redis, matar worker, forcar lag DB).
## Correção proposta

— Rodar mensalmente:

- Desabilitar Upstash Redis → confirmar rate-limit degrada graciosamente (mas ver [2.x] sobre fail-open).
- Matar Supabase Edge Function → verificar retries.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.9).