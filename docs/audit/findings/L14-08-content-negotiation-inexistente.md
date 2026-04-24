---
id: L14-08
audit_ref: "14.8"
lens: 14
title: "Content negotiation inexistente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["security-headers", "mobile"]
files:
  - docs/api/CONTENT_NEGOTIATION_POLICY.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform+product
runbook: docs/api/CONTENT_NEGOTIATION_POLICY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Política ratificada em `docs/api/CONTENT_NEGOTIATION_POLICY.md`.
  Decisão deliberada: **um shape por URL** (CSV/ICS/PDF moram
  em rotas separadas com sufixo `.csv`/`.ics`/`.pdf`) em vez de
  `Accept`-header negotiation no mesmo endpoint. Justificado por
  cache poisoning surface (Vary: Accept frágil em CDN tiers),
  OpenAPI tooling mais limpo (TS + Dart codegen), audit-log
  legibilidade, e modelo de auth diferente entre JSON-list e
  CSV-export. Documento define naming convention e headers
  honrados (`Accept-Language`, `Idempotency-Key`,
  `If-None-Match`) vs ignorados (`Accept: application/xml`,
  `Accept-Charset`, `Range` em JSON).
---
# [L14-08] Content negotiation inexistente
> **Lente:** 14 — Contracts · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Todos endpoints hardcoded `application/json`. Export CSV precisa de endpoint separado `/api/export/...` vs `/api/... (Accept: text/csv)`.
## Correção proposta

— Single endpoint, negocia via `Accept` header. OpenAPI doc descreve.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.8).