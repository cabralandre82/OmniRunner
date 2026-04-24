---
id: L14-07
audit_ref: "14.7"
lens: 14
title: "Sem idempotency-key header em POSTs financeiros"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["idempotency", "security-headers", "reliability"]
files:
  - docs/api/IDEMPOTENCY_CONTRACT.md
  - docs/runbooks/IDEMPOTENCY_RUNBOOK.md
  - portal/src/lib/api/idempotency.ts
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform+finance
runbook: docs/runbooks/IDEMPOTENCY_RUNBOOK.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Contrato consolidado em `docs/api/IDEMPOTENCY_CONTRACT.md`. A
  infraestrutura já existe (L18-02:
  `withIdempotency()` + tabela `idempotency_keys` write-once com
  GC horário + `IDEMPOTENCY_RUNBOOK.md`). O finding agora aponta
  para o contrato canônico que enumera as 11 rotas in-scope, as
  3 categorias out-of-scope (swap, GET, webhooks de provider que
  carregam própria key), o storage server-side, e a semântica de
  falha (`MISSING_IDEMPOTENCY_KEY` / `IDEMPOTENCY_KEY_CONFLICT`
  / `IDEMPOTENCY_KEY_INFLIGHT`). CI guard
  `audit:idempotency-coverage` listado como follow-up
  não-blocking.
---
# [L14-07] Sem idempotency-key header em POSTs financeiros
> **Lente:** 14 — Contracts · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Relacionado a [1.5]. Padrão Stripe: `Idempotency-Key: <uuid>` header aceito em POST, retry seguro no cliente.
## Correção proposta

—

```typescript
const idemKey = req.headers.get("idempotency-key");
if (!idemKey || !isUUID(idemKey)) {
  return apiError("IDEMPOTENCY_REQUIRED", "…", 400);
}
// Store {idem_key → response} for 24h; replay on retry
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.7).