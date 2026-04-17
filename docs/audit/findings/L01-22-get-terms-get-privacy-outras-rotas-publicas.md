---
id: L01-22
audit_ref: "1.22"
lens: 1
title: "GET /terms, GET /privacy, outras rotas públicas"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "webhook", "mobile", "portal"]
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
# [L01-22] GET /terms, GET /privacy, outras rotas públicas
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Visitantes
## Achado
Middleware lista apenas `/login`, `/no-access`, `/api/auth/callback`, `/api/health`, `/api/custody/webhook`, `/api/liveness` e prefixos `/challenge/`, `/invite/`. **Não há `/terms` ou `/privacy` em `PUBLIC_ROUTES`** — se existirem em `src/app`, o middleware exige autenticação, bloqueando visitantes não logados de ler TOS. Isso pode ser intencional (landing page separada) mas merece confirmar.
## Correção proposta

Confirmar se existe landing page em `/terms`, `/privacy`. Se sim, adicionar ao middleware.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.22]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.22).