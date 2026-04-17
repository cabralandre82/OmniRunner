---
id: L03-19
audit_ref: "3.19"
lens: 3
title: "NFS-e / fiscal — Não observado"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["finance"]
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
# [L03-19] NFS-e / fiscal — Não observado
> **Lente:** 3 — CFO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** N/A
**Personas impactadas:** —
## Achado
Não encontrei integração com Nuvem Fiscal ou qualquer provedor de NFS-e no repo. O modelo B2B de custódia/clearing gera **receita da plataforma** (platform_revenue) — essa receita é sujeita a PIS/COFINS/ISS no Brasil. Não ver código de emissão fiscal é uma bandeira de "não-conformidade operacional".
## Risco / Impacto

Receita Federal / prefeitura autua a plataforma por falta de emissão de NFS-e sobre fees B2B.

## Correção proposta

Consultar contador e implementar emissão mensal de NFS-e sobre agregado de `platform_revenue` para cada assessoria (devedor). Adicionar job `monthly-invoice-generation`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.19).