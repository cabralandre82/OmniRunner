---
id: L07-06
audit_ref: "7.6"
lens: 7
title: "Timezone sem configuração do usuário"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal"]
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
# [L07-06] Timezone sem configuração do usuário
> **Lente:** 7 — CXO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `sessions.start_time_ms` é UTC timestamp. Portal renderiza datas com `new Date(ms).toLocaleString("pt-BR")` → respeita timezone do browser, mas:

- Atleta no Brasil em fuso `America/Noronha` vê "3:00 AM" quando rodou às "4:00 AM locais".
- Portal admin vendo atletas de grupos em múltiplos países mistura fusos.
## Correção proposta

— Campo `profiles.timezone text DEFAULT 'America/Sao_Paulo'` detectado no primeiro login. Backend formata datas server-side quando necessário.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.6).