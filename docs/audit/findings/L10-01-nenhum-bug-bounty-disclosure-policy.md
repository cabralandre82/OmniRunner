---
id: L10-01
audit_ref: "10.1"
lens: 10
title: "Nenhum bug bounty / disclosure policy"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["rls", "portal"]
files: []
correction_type: code
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