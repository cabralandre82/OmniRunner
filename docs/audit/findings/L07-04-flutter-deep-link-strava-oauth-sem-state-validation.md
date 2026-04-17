---
id: L07-04
audit_ref: "7.4"
lens: 7
title: "Flutter deep link Strava OAuth sem state validation (CSRF)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["integration", "mobile", "ux", "seo"]
files:
  - omni_runner/lib/core/deep_links/deep_link_handler.dart
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
# [L07-04] Flutter deep link Strava OAuth sem state validation (CSRF)
> **Lente:** 7 — CXO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Já citado em PARTE 1 [1.20] — `omni_runner/lib/core/deep_links/deep_link_handler.dart`. Crítico UX também: atleta tenta conectar, é redirecionado de volta, o app abre mas **não confirma sucesso** porque state não é verificado. Comportamento indeterminado.
## Correção proposta

— Gerar `state = secureRandom(32)` antes do OAuth, armazenar em `FlutterSecureStorage`, verificar match no callback. UX: toast "Conectado ao Strava ✓" só quando state confere.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.4).