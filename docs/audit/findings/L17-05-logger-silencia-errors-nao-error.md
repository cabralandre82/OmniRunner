---
id: L17-05
audit_ref: "17.5"
lens: 17
title: "Logger silencia errors não-Error"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "observability"]
files:
  - portal/src/lib/logger.ts
correction_type: code
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
# [L17-05] Logger silencia errors não-Error
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/logger.ts:31-35`:

```31:35:portal/src/lib/logger.ts
    if (error instanceof Error) {
      Sentry.captureException(error, { extra: { msg, ...meta } });
    } else if (error) {
      Sentry.captureMessage(msg, { level: "error", extra: { error, ...meta } });
    }
```

Chamada `logger.error("failed", undefined)` passa pelo segundo branch (undefined é falsy), **não captura nada no Sentry**.
## Correção proposta

—

```typescript
error(msg: string, error?: unknown, meta?: LogMeta) {
  const errorInfo = error instanceof Error
    ? { message: error.message, stack: error.stack }
    : error !== undefined ? { value: String(error) } : {};
  console.error(format("error", msg, { ...meta, ...errorInfo }));

  // Always report to Sentry, even without error object
  if (error instanceof Error) {
    Sentry.captureException(error, { extra: { msg, ...meta } });
  } else {
    Sentry.captureMessage(msg, { level: "error", extra: { error, ...meta } });
  }
},
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.5).