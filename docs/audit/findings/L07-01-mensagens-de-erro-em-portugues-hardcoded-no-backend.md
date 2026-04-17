---
id: L07-01
audit_ref: "7.1"
lens: 7
title: "Mensagens de erro em português hardcoded no backend"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "testing"]
files:
  - portal/src/app/api/swap/route.ts
correction_type: process
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
# [L07-01] Mensagens de erro em português hardcoded no backend
> **Lente:** 7 — CXO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
—

```143:143:portal/src/app/api/swap/route.ts
    return NextResponse.json({ error: "Operação falhou. Tente novamente." }, { status: 422 });
```

Vários endpoints retornam strings pt-BR hardcoded. Frontend mobile (`omni_runner`) tem i18n (`app_localizations_en.dart`, `app_localizations_pt.dart`) mas quando bate na API recebe pt-BR só.
## Risco / Impacto

— Usuário inglês (expansão internacional) vê mensagem em português → percepção de produto amador.

## Correção proposta

— API sempre retorna `{ error: { code: "SWAP_OPERATION_FAILED" } }`. Cliente traduz via tabela i18n.

## Teste de regressão

— Contract test: todas as rotas `/api/*` retornam `error.code` (upper snake), não `error` string.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.1).