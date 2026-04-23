---
id: L10-01
audit_ref: "10.1"
lens: 10
title: "Nenhum bug bounty / disclosure policy"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["rls", "portal"]
files:
  - SECURITY.md
  - portal/public/.well-known/security.txt
  - docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md
  - tools/audit/check-security-disclosure.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-security-disclosure.ts
linked_issues: []
linked_prs:
  - local:77c4992
owner: security
runbook: docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Published the full vulnerability disclosure stack:
  (a) SECURITY.md at repo root with reporting instructions, scope,
      safe harbour, and resolution SLA table (24h/72h/14d for
      critical down to 10d/next-release/180d for low);
  (b) /.well-known/security.txt (RFC 9116) with Expires date in the
      future, Contact, Policy, Canonical, Preferred-Languages;
  (c) Internal triage runbook with 14-day cadence, hostile-reporter /
      duplicate / leaked-PoC playbooks;
  (d) CI guard (27 invariants) that rejects stale security.txt,
      missing SLA table, missing safe-harbour clause, and missing
      runbook cross-link.
  Public bug bounty program remains deferred until after the first
  external penetration test (tracked by L10-02 threat-model review
  history) — retroactive rewards are committed in SECURITY.md.
---
# [L10-01] Nenhum bug bounty / disclosure policy
> **Lente:** 10 — CSO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `security.txt`, `/security`, `SECURITY.md` — nada. Pesquisador que descubra falha não sabe como reportar.
## Risco / Impacto

— Findings vazam em fóruns/Twitter antes de correção. Zero-day exploitado em produção.

## Correção proposta

—

```
# portal/public/.well-known/security.txt
Contact: security@omnirunner.com
Expires: 2027-04-17T00:00:00.000Z
Preferred-Languages: pt, en
Policy: https://omnirunner.com/security-policy
Canonical: https://omnirunner.com/.well-known/security.txt
```

+ `SECURITY.md` no repo com SLA de resposta. Considerar YesWeHack, Intigriti ou HackerOne privado após primeira auditoria externa.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.1).