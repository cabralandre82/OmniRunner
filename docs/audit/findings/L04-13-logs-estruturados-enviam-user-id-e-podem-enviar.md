---
id: L04-13
audit_ref: "4.13"
lens: 4
title: "Logs estruturados enviam user_id e podem enviar ip_address ao Sentry"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "observability", "reliability"]
files:
  - portal/src/lib/logger.ts
  - portal/src/lib/observability/sentryPii.ts
  - portal/src/lib/observability/sentryPii.test.ts
  - portal/sentry.client.config.ts
  - portal/sentry.server.config.ts
  - portal/sentry.edge.config.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/observability/sentryPii.test.ts
linked_issues: []
linked_prs: []
owner: platform-security
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Sentry agora tem `sendDefaultPii: false` em todos os 3
  runtimes (client/server/edge) **+** `stripPii()` rodando como
  última etapa de `beforeSend` / `beforeSendTransaction`. O
  helper canônico (`portal/src/lib/observability/sentryPii.ts`)
  zera `user.email`/`user.ip_address` (mantém apenas
  `user.id` — UUID pseudonimizado, necessário para triagem),
  remove `Authorization`/`Cookie`/`x-forwarded-for` dos
  headers (allow-list só com `user-agent`, `x-request-id`,
  `x-omni-client`, `Referer`), apaga `request.cookies`,
  `request.query_string`, `request.data` e
  `contexts.request.client_ip`. 7 vitest cases cobrem o
  comportamento. Defesa-em-profundidade: mesmo se uma chamada
  legacy `Sentry.setUser({ email })` resurgir, `stripPii`
  intercepta antes do envio.
---
# [L04-13] Logs estruturados enviam user_id e podem enviar ip_address ao Sentry
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/logger.ts` passa `user.id` para Sentry. Configuração Sentry provavelmente já redige IPs mas não está explícito no `sentry.server.config.ts`.
## Correção proposta

—

```typescript
Sentry.init({
  beforeSend(event) {
    if (event.user) { delete event.user.ip_address; delete event.user.email; }
    return event;
  },
  sendDefaultPii: false,
});
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.13).