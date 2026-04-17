---
id: L10-09
audit_ref: "10.9"
lens: 10
title: "Falta defesa anti credential stuffing no Mobile/Portal"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["rate-limit", "edge-function", "testing"]
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
# [L10-09] Falta defesa anti credential stuffing no Mobile/Portal
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase Auth faz rate-limit por IP mas não por email. Ataque distribuído testa mil emails × senha comum.
## Correção proposta

— Supabase Edge Function pré-login que mantém contador por `email_hash` e aplica `CAPTCHA` (hCaptcha) após 3 falhas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.9).