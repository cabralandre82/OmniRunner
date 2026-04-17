---
id: L20-08
audit_ref: "20.8"
lens: 20
title: "Post-mortem template ausente"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
files:
  - docs/postmortems/TEMPLATE.md
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L20-08] Post-mortem template ausente
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `docs/` não tem template de post-mortem blameless. Depois de incidente, aprendizado se perde.
## Correção proposta

— `docs/postmortems/TEMPLATE.md` + diretório com PMs históricos. Estrutura Google SRE:

- Incident summary
- Timeline
- Root cause
- Trigger
- Resolution
- Action items (owner + deadline)
- Lessons learned

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.8).