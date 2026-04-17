---
id: L20-03
audit_ref: "20.3"
lens: 20
title: "Sem tracing distribuído (OpenTelemetry)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "security-headers", "mobile", "portal", "edge-function"]
files:
  - portal/src/instrumentation.ts
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
# [L20-03] Sem tracing distribuído (OpenTelemetry)
> **Lente:** 20 — SRE · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Request do mobile → Portal `/api/distribute-coins` → Supabase RPC → possivelmente edge function → webhook → banco. Não há trace_id correlacionado end-to-end.
## Risco / Impacto

— "Pagamento demorou 15 segundos" — impossível saber onde (mobile? portal? RPC? network?).

## Correção proposta

—

```typescript
// portal/src/instrumentation.ts
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: "https://otel.omnirunner.com/v1/traces" }),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

Supabase client: wrap em `span`. Mobile Flutter: `sentry_flutter` já captura; habilitar tracing + propagar `sentry-trace` header para API.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.3).