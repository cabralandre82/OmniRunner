---
id: L10-02
audit_ref: "10.2"
lens: 10
title: "Threat model formal não documentado"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "portal", "testing"]
files:
  - docs/security/THREAT_MODEL.md
  - tools/audit/check-threat-model.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-threat-model.ts
linked_issues: []
linked_prs:
  - local:05cec54
owner: security
runbook: docs/security/THREAT_MODEL.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Formal STRIDE + DFD document at docs/security/THREAT_MODEL.md.
  Six trust boundaries (TB1 network … TB6 backup), textual DFD of
  Mobile ↔ Portal ↔ Supabase ↔ Stripe / Asaas / Strava / Sentry,
  STRIDE table per boundary with mitigation status (✅/🟡/⏳) and
  linked finding IDs, ranked asset list headed by OmniCoin ledger
  and service-role key, severity-bump rules feeding L10-01 SLAs,
  6-story abuse catalogue, 90-day / major-feature review cadence.
  Strava-only architectural decision (Sprint 25.0.0) explicitly
  acknowledged — rows about live in-app GPS tracking were reclassified
  wont-fix in the accompanying audit sweep. CI guard audit:threat-model
  (33 invariants) keeps coverage locked.
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