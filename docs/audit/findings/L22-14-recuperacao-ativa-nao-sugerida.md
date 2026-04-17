---
id: L22-14
audit_ref: "22.14"
lens: 22
title: "Recuperação ativa não sugerida"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["personas", "athlete-amateur"]
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
# [L22-14] Recuperação ativa não sugerida
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador faz 3 corridas seguidas pesadas → lesão. Sem sistema que sugira "descansar" ou "caminhada".
## Correção proposta

— Regra heurística em `generate-fit-workout`: se últimos 3 dias tiveram TSS alto → próximo treino é "descanso ativo/caminhada 20 min".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.14).