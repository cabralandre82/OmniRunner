---
id: L23-15
audit_ref: "23.15"
lens: 23
title: "CRM para captação de atletas"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["personas", "coach", "crm", "marketing"]
files:
  - docs/product/COACH_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "fce133b"

owner: product+backend+portal
runbook: docs/product/COACH_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/COACH_BASELINE.md` § 1
  (Lead-to-athlete CRM funnel). Extensão do CRM
  existente (`staff_crm_list_screen` = in-group) com
  duas novas fases do funil: `lead` e `trial`. Nova
  tabela `coaching_leads` (source, UTM, referral,
  status) + RLS scoped por `coaching_members` staff.
  Ingestão via form público em `/c/{slug}` → POST
  `/api/coach/leads` rate-limited; atribuição via cookie
  `omni_att` de L15-01. UI Kanban em `/platform/crm/
  funnel`. Ship Wave 5 fase W5-D (depende do marketing-
  site estar pronto para o form público).
---
# [L23-15] CRM para captação de atletas
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `crm` module existe. Auditoria superficial. Coach B2B precisa: lead captured via landing → trial 30 dias → conversão. Funnel.
## Correção proposta

— CRM lead-to-athlete pipeline; source attribution ([15.1]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.15).
- `2026-04-24` — Consolidado em `docs/product/COACH_BASELINE.md` § 1 (batch K12); implementação Wave 5 fase W5-D.
