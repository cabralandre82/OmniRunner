---
id: L18-07
audit_ref: "18.7"
lens: 18
title: "userBucket em feature-flags usa hash Java-style (inseguro, colisões)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["cron"]
files: []
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
# [L18-07] userBucket em feature-flags usa hash Java-style (inseguro, colisões)
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 43-51 implementam hash `(hash << 5) - hash + charCodeAt`. Não é crypto-secure nem uniform. Para split 50/50 funciona, mas para 90/10 distribuição pode ser enviesada.
## Correção proposta

— Usar `crypto.subtle.digest` (Web Crypto):

```typescript
async function userBucket(userId: string, key: string): Promise<number> {
  const data = new TextEncoder().encode(`${userId}:${key}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return new DataView(hash).getUint32(0) % 100;
}
```

Trade-off: assíncrono. Vale pela robustez estatística em A/B.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.7).