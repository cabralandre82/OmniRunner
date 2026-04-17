---
id: L10-02
audit_ref: "10.2"
lens: 10
title: "Threat model formal não documentado"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "testing"]
files:
  - docs/security/THREAT_MODEL.md
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L10-02] Threat model formal não documentado
> **Lente:** 10 — CSO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep -ri "threat_model\|STRIDE\|DFD" docs/` → vazio. Sistema com custódia financeira sem DFD nem STRIDE = segurança orgânica.
## Risco / Impacto

— Cada mudança arquitetural é avaliada ad-hoc; controles derivam de "lembrei de testar isso" ao invés de matriz sistemática.

## Correção proposta

— Documento `docs/security/THREAT_MODEL.md` com:

- Data Flow Diagrams: Mobile ↔ Portal ↔ Supabase ↔ Gateways
- Trust boundaries explícitos
- STRIDE por boundary
- Mitigações mapeadas para commits/PRs

Revisão a cada major feature.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.2).