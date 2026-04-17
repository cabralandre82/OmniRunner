---
id: L01-34
audit_ref: "1.34"
lens: 1
title: "Flutter — getOrCreateKey SHA-256 ofuscação é redundante"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["mobile"]
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
# [L01-34] Flutter — getOrCreateKey SHA-256 ofuscação é redundante
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** APP
**Personas impactadas:** N/A (design)
## Achado
`db_secure_store.dart:53-58` gera 32 random bytes e passa por SHA-256. É desnecessário (Random.secure() já dá 32 bytes uniformes), mas não é inseguro.
## Correção proposta

Simplificar para `return randomBytes;` — economiza CPU no cold start. Não bloqueante.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.34]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.34).