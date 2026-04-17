---
id: L01-24
audit_ref: "1.24"
lens: 1
title: "/invite/[code] — Rota pública de aceite de convite"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["rate-limit", "mobile", "portal", "seo"]
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
# [L01-24] /invite/[code] — Rota pública de aceite de convite
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Atleta convidado
## Achado
Público via middleware. Deep link no app também (`deep_link_handler.dart:118`). Precisa auditar: (a) se aceita códigos inválidos graciosamente; (b) rate limit para evitar enumeração; (c) não vaza membership de outros atletas.
## Correção proposta

Auditar `portal/src/app/invite/[code]/page.tsx`. Confirmar rate limit IP-based.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.24]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.24).