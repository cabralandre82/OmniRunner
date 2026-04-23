---
id: L17-05
audit_ref: "17.5"
lens: 17
title: "Logger silencia errors não-Error"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "observability", "sentry"]
files:
  - portal/src/lib/logger.ts
  - tools/audit/check-logger-sentry-capture.ts
  - docs/runbooks/LOGGER_SENTRY_CAPTURE_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - portal/src/lib/logger.test.ts
linked_issues: []
linked_prs:
  - "4549616"
owner: portal
runbook: docs/runbooks/LOGGER_SENTRY_CAPTURE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "2026-04-21 — fixed. logger.error now unconditionally reports to Sentry (captureException for Error, captureMessage for everything else including undefined/null). normalizeErrorFields helper produces a consistent console log shape. 4 production call-sites (custody webhook × 3, checkout proxy) are now observable in Sentry. CI npm run audit:logger-sentry-capture (8 regressions) + runbook."
---
# [L17-05] Logger silencia errors não-Error
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
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
- `2026-04-21` — Corrigido. Refatorado `portal/src/lib/logger.ts`: (a) novo helper `normalizeErrorFields(error)` que retorna `{}` para `undefined`/`null`, `{error, stack}` para `Error`, e `{error: <coerced>}` para strings/números/objetos/arrays; (b) o branch `else if (error)` foi trocado por um fallback **incondicional** `Sentry.captureMessage(msg, { level: 'error', extra: { ...meta, ...errorFields } })` quando `error` não é `Error`, com `return;` após `captureException` para curto-circuitar o path de Error. **Impacto**: 4 call-sites em produção (`custody.webhook.config_missing` × 2, `custody.webhook.dispute_feature_unavailable`, `checkout.proxy.gateway_non_json`) que chamavam `logger.error("...", undefined, meta)` e silenciosamente dropavam do Sentry agora emitem. **Tests**: suite `L17-05 Sentry capture invariants` com 6 casos (Error, undefined, null, string, plain object, console-format) — 14/14 passam em `portal/src/lib/logger.test.ts`. **CI**: `npm run audit:logger-sentry-capture` (`tools/audit/check-logger-sentry-capture.ts`) com 8 regressions enforça (i) ausência do bug shape `} else if (error) {` antes de `captureMessage`, (ii) presença de ambos os paths `captureException`/`captureMessage`, (iii) helper `normalizeErrorFields` declarado, (iv) tratamento explícito `undefined|null` como `{}`, (v) test suite com asserts dos 3 shapes críticos. **Runbook**: `docs/runbooks/LOGGER_SENTRY_CAPTURE_RUNBOOK.md` documenta invariante, anti-patterns, detection signal (Sentry:Log ratio ≥ 0.95), e 4 playbooks operacionais. Backwards-compat: sintaxe do caller inalterada; apenas eventos antes dropados passam a surface em Sentry.