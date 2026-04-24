---
id: L03-16
audit_ref: "3.16"
lens: 3
title: "Consistência entrada–saída de FX"
severity: medium
status: duplicate
wave: 2
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["portal", "fx"]
files: []
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: finance
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L01-02
deferred_to_wave: null
note: |
  Fechado como **duplicate de L01-02** ("FX rate
  client-supplied"). A solução autoritária para FX já foi
  embarcada em Onda 0: `platform_fx_quotes` (server-side
  authoritative), endpoint `GET /api/fx/quote` read-only para
  UI, e `.strict()` Zod schemas em todos os handlers que aceitam
  amount em USD. Entrada e saída agora consultam o mesmo
  snapshot identificado por `quote_id`, eliminando assimetria
  entre custody.deposit (entrada) e custody.withdraw (saída).
  Cross-ref: L03-06 (FX spread cálculo simétrico) também já
  fechado em K3.
---
# [L03-16] Consistência entrada–saída de FX
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
_(sem descrição detalhada — ver relatório original em `docs/audit/parts/`)_
## Correção proposta

Remover `fx_rate` do client-side; buscar rate server-side.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.16).