---
id: L09-12
audit_ref: "9.12"
lens: 9
title: "Auditoria externa financeira — inexistente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: []
files:
  - docs/policies/EXTERNAL_FINANCIAL_AUDIT.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - d3488b4
  - ba3c71e
owner: finance+cro
runbook: docs/policies/EXTERNAL_FINANCIAL_AUDIT.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Policy ratified in docs/policies/EXTERNAL_FINANCIAL_AUDIT.md:
  voluntary external financial audit starting Year 2 (calendar
  2027 covering FY 2026), mid-market vendor (BDO/Grant Thornton/
  Mazars) at BRL 80-150k. Scope: financial statements + custody
  reconciliation (check_custody_invariants + per-group breakdown
  via SECURITY DEFINER RPC) + clearing-pipeline integrity
  (paired ledger entries per L02-07/ADR-008 invariant) + revenue
  recognition. Year 1 pre-audit checklist (audit-ready ledger,
  domain audit_logs, doc repos) is largely complete via Wave 1;
  the only gating Year-1-Q4 item is the audit-dossier directory
  with close-of-books materials.
---
# [L09-12] Auditoria externa financeira — inexistente
> **Lente:** 9 — CRO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Produto lida com dinheiro real mas não há provisão para auditoria anual independente (Big 4 ou similar) mesmo que voluntária para gerar confiança.
## Correção proposta

— Plano para auditoria a partir de Ano 2 de operação.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.12).