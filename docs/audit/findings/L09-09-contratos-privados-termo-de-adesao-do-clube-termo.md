---
id: L09-09
audit_ref: "9.9"
lens: 9
title: "Contratos privados (termo de adesão do clube, termo de atleta) inexistentes no repo"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd"]
files:
  - docs/legal/TERMO_ADESAO_ASSESSORIA.md
  - docs/legal/TERMO_ATLETA.md
correction_type: docs
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
# [L09-09] Contratos privados (termo de adesão do clube, termo de atleta) inexistentes no repo
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep -rn "termo_adesao\|termo_atleta\|contrato" docs/` não encontra versões legíveis, revisadas.
## Correção proposta

— `docs/legal/TERMO_ADESAO_ASSESSORIA.md`, `docs/legal/TERMO_ATLETA.md`, versionados no git com hash SHA-256 gravado em `consent_log.version` ([4.3]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.9).