---
id: L01-23
audit_ref: "1.23"
lens: 1
title: "/challenge/[id] — Rota pública"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["gps", "mobile", "portal"]
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
# [L01-23] /challenge/[id] — Rota pública
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Atleta (recebendo convite), Público
## Achado
`PUBLIC_PREFIXES` inclui `/challenge/`. Página pública deve mostrar apenas dados resumidos do desafio (título, participantes N, status), sem PII de atletas. Código não lido.
## Correção proposta

Auditar `portal/src/app/challenge/[id]/page.tsx` — verificar que não expõe nome completo, emails, GPS tracks.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.23]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.23).