---
id: L14-02
audit_ref: "14.2"
lens: 14
title: "Sem versionamento de path (/api/v1)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "security-headers", "mobile", "migration", "reliability"]
files:
  - portal/src/lib/api/versioning.ts
  - portal/src/middleware.ts
  - portal/src/app/api/v1/swap/route.ts
  - portal/src/app/api/v1/custody/route.ts
  - portal/src/app/api/v1/custody/withdraw/route.ts
  - portal/src/app/api/v1/distribute-coins/route.ts
  - portal/src/app/api/v1/clearing/route.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/api/versioning.test.ts
  - portal/src/app/api/v1/v1-aliases.test.ts
linked_issues: []
linked_prs:
  - cc6b3e1
owner: backend-platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Migração path-versioning concluída para os 5 endpoints financeiros
  do escopo da auditoria:
    - /api/v1/swap, /api/v1/custody, /api/v1/custody/withdraw,
      /api/v1/distribute-coins, /api/v1/clearing.
  Cada alias é um arquivo de 5-10 linhas que delega para o handler
  legacy via `wrapV1Handler(legacy)` — handler legacy permanece como
  source-of-truth do business logic; só transport headers diferem.

  Headers emitidos pelo middleware (L14-02):
    - todo `/api/*` recebe `X-Api-Version: 1`;
    - rotas legacy financeiras adicionalmente recebem
      `Deprecation: true`,
      `Sunset: <DEFAULT_FINANCIAL_SUNSET>` (RFC 8594, atualmente
      2027-01-01 UTC), e
      `Link: </api/v1/...>; rel="successor-version"` apontando para
      o successor v1.

  Camada se compõe corretamente com:
    - L13-06 (`x-request-id`) — preservado,
    - L14-04/05/06 — handlers já usam envelope canônico, identity
      rate-limit e cursor pagination; aliases v1 herdam por construção,
    - L14-01 — paths v1 documentados como exemplares contract-first.

  Out-of-scope:
    - /api/custody/webhook (contrato Stripe inbound — não consumer-facing),
    - /api/custody/fx-quote (não listado no escopo da auditoria).
    - Migração efetiva dos clientes (mobile + B2B) ao v1: o header
      `Sunset` sinaliza intenção; flips são atividades de release
      coordenadas fora deste PR.

  Commits:
    - cc6b3e1 (feat /api/v1 path versioning + Sunset headers)
---
# [L14-02] Sem versionamento de path (/api/v1)
> **Lente:** 14 — Contracts · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Rotas são `/api/custody`, `/api/swap`, `/api/distribute-coins`. Primeira mudança quebra:

- App mobile versão < atual em campo
- Integração de parceiro B2B
- Scripts internos de BI
## Correção proposta

— Migration gradual:

1. Mover endpoints financeiros críticos (`/api/custody`, `/api/swap`, `/api/distribute-coins`, `/api/clearing`, `/api/custody/withdraw`) para `/api/v1/...`.
2. Retornar header `Sunset: Wed, 01 Jan 2027 00:00:00 GMT` nas rotas sem versão.
3. Responses incluem `X-Api-Version: 1`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.2).