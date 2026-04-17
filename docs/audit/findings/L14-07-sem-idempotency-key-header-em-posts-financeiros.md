---
id: L14-07
audit_ref: "14.7"
lens: 14
title: "Sem idempotency-key header em POSTs financeiros"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["idempotency", "security-headers", "reliability"]
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