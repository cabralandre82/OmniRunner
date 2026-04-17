---
id: L05-14
audit_ref: "5.14"
lens: 5
title: "Feed social: sem \"report\" / moderação"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["migration", "ux"]
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
# [L05-14] Feed social: sem "report" / moderação
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Posts, comments, reactions existem mas não há tabela `reports` nem fluxo de moderação.
## Risco / Impacto

— Cyberbullying entre atletas. Marco Civil Art. 19 + novas regras de plataformas.

## Correção proposta

— `CREATE TABLE social_reports(...)` + tela `/platform/moderation` + hide automático após 3 reports distintos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.14).