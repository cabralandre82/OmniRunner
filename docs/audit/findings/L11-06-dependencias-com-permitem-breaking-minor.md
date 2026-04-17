---
id: L11-06
audit_ref: "11.6"
lens: 11
title: "Dependências com ^ permitem breaking minor"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal"]
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
# [L11-06] Dependências com ^ permitem breaking minor
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/package.json`: `next: ^14.2.15`, `zod: ^4.3.6`. Caret permite minor bumps que podem quebrar tipos (zod 4 ↔ 3).
## Correção proposta

— `^` aceitável para produção SE houver CI de integração robusto. Pinar exatos (`14.2.15`) para `next`, `@supabase/ssr` em `package.json` + `.npmrc` `save-exact=true`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.6).