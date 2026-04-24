---
id: L07-09
audit_ref: "7.9"
lens: 7
title: "Notificações push: sem deep link preciso"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "ux"]
files:
  - omni_runner/lib/core/push/push_navigation_handler.dart
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 9a74988

owner: mobile
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  `push_navigation_handler.dart` ganha **escape hatch genérico
  de deep-link**: payloads com `data.route` (ex.
  `/workout-delivery/123`) navegam direto via `pushNamed`,
  caindo para o switch por `type` apenas se a rota não estiver
  na allowlist. Allowlist de 10 rotas (`/today`, `/wallet`,
  `/championships`, `/workout-delivery`, etc.) com suporte a
  `<prefix>/<id>` e querystring. Hardening: backend pode
  introduzir novos tipos de notificação sem app-update; rota
  não-allowlist é silenciosamente ignorada (defesa contra
  servidor comprometido tentando navegar para rota inesperada).
---
# [L07-09] Notificações push: sem deep link preciso
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/core/push/push_navigation_handler.dart` abre a tela home ou última tela. Notificação "Você tem novo workout delivery" não abre direto o item.
## Correção proposta

— Payload push incluir `data: { route: "/workout-delivery/123" }` e handler navegar com `context.go(route)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.9).