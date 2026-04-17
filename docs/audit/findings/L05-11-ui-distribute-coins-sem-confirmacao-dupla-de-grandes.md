---
id: L05-11
audit_ref: "5.11"
lens: 5
title: "UI distribute-coins: sem confirmação dupla de grandes valores"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files: []
correction_type: code
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
# [L05-11] UI distribute-coins: sem confirmação dupla de grandes valores
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/(portal)/distribute/...` presumivelmente tem um único botão "Distribuir". Sem modal "Você está distribuindo 50.000 moedas (≈ US$ 50.000). Digite CONFIRMAR.".
## Risco / Impacto

— Fat finger: coach queria 50 e digitou 5000.

## Correção proposta

— UI: quando `amount > 1000 OR amount * athletes > 5000` → modal de confirmação textual (tipo o "type DELETE to confirm" do GitHub).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.11).