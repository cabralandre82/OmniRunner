---
id: L02-13
audit_ref: "2.13"
lens: 2
title: "/api/inngest — Não existe no código"
severity: na
status: not-reproducible
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["portal", "cron"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: confirmado — Omni Runner usa pg_cron + Edge Functions, não Inngest. Zero matches no grep."
---
# [L02-13] /api/inngest — Não existe no código
> **Lente:** 2 — CTO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔍 not-reproducible
**Camada:** N/A
**Personas impactadas:** —

## Achado original
O prompt original da auditoria referenciava Inngest (Clinipharma). Omni Runner usa `pg_cron` + Supabase Edge Functions.

## Re-auditoria 2026-04-24

Busca exaustiva: `rg -i inngest portal/ omni_runner/ supabase/ package.json package-lock.json` → **zero matches**.

- `portal/src/app/api/inngest/` → não existe
- `package.json` dependencies → sem `inngest`, `@inngest/*`
- Stack real está documentada em `docs/STACK.md` (pg_cron + Edge Functions)

**Nada a fazer — achado não se aplica a este projeto.** Mantido por rastreabilidade (item 2.13 do relatório inicial).

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.13]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.13).
- `2026-04-24` — Re-auditoria confirmou que Inngest não existe no codebase. Flipped para `not-reproducible`.
