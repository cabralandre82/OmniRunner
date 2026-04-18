---
id: L20-03
audit_ref: "20.3"
lens: 20
title: "Sem tracing distribuído (OpenTelemetry)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["sre", "observability", "mobile", "portal", "tracing"]
files:
  - portal/src/instrumentation.ts
  - portal/src/lib/observability/tracing.ts
  - portal/src/lib/observability/tracing.test.ts
  - portal/src/lib/audit.ts
  - portal/src/lib/audit.test.ts
  - portal/src/lib/logger.ts
  - portal/src/lib/logger.test.ts
  - portal/src/app/api/distribute-coins/route.ts
  - omni_runner/lib/main.dart
  - omni_runner/lib/core/http/traced_http_client.dart
  - omni_runner/test/core/http/traced_http_client_test.dart
  - docs/observability/TRACING.md
correction_type: feature
test_required: true
tests:
  - portal/src/lib/observability/tracing.test.ts
  - portal/src/lib/audit.test.ts
  - portal/src/lib/logger.test.ts
  - omni_runner/test/core/http/traced_http_client_test.dart
linked_issues: []
linked_prs:
  - "commit:0050d00"
owner: sre
runbook: docs/observability/TRACING.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Corrigido em commit `0050d00`. Estratégia: "OpenTelemetry-compatible tracing
  via Sentry" — em vez de adicionar `@opentelemetry/sdk-node` + um exportador
  OTLP separado (Tempo/Honeycomb/etc), aproveita a integração Sentry/Next.js
  que fala OTel semconv internamente (Sentry SDK 10+ usa `@opentelemetry/api`).
  Single trace pipeline, sem custo dobrado, sem risco de divergência entre
  dois SDKs. Mesmas garantias end-to-end de propagação W3C/Sentry-trace +
  mesma UI de trace tree.

  ## O que foi feito

  ### Portal (Next.js)

  - **`portal/src/instrumentation.ts`** (novo): bootstrap entrypoint do
    Next.js. Roda ANTES da primeira request, registrando o Sentry SDK no
    runtime correto (`nodejs` vs `edge`) e fornece `onRequestError` hook
    que correlaciona erros 5xx → trace_id em logs estruturados.

  - **`portal/src/lib/observability/tracing.ts`** (novo): façade fina sobre
    `@sentry/nextjs` (que re-exporta `@sentry/core` via `@sentry/node`).
    API pública:
      * `withSpan(name, op, fn, attrs?)` — wrap async fn em span Sentry/OTel
      * `currentTraceId()` / `currentSpanId()` — leitura via `Sentry.spanToJSON()`
      * `traceparent()` — gera headers `sentry-trace` + `baggage` para
        outbound fetch a serviços first-party
      * `continueTraceFromRequest(headers, cb)` — resume trace inbound
    Convenções de atributos OTel semconv-aligned (`db.system`,
    `db.operation`, `http.method`) + domain attrs (`omni.actor_id`,
    `omni.group_id`). Tipo literal `SpanOp` enumera operações suportadas
    para discover queries consistentes. **17 testes unitários verdes**.

  - **`portal/src/lib/audit.ts`**: `auditLog()` agora auto-injeta
    `trace_id` + `span_id` em `metadata` quando há span ativo. Caller pode
    sobrescrever (cenário replay/backfill de webhook que quer preservar o
    trace_id original). Toda escrita também passa por `withSpan("audit
    ${action}", "audit.write", ...)` para aparecer na trace tree. **+4
    testes** cobrindo: auto-injeção, respect a caller-provided trace_id,
    ausência de trace_id quando sem span, metadata ausente.

  - **`portal/src/lib/logger.ts`**: cada log line auto-carrega `trace_id`
    + `span_id` via `Sentry.spanToJSON()`. Logger nunca falha quando
    Sentry não está inicializado (try/catch defensivo). **+4 testes**.

  - **`portal/src/app/api/distribute-coins/route.ts`**: rota crítica
    (financeira) wired com `withSpan("rpc emit_coins_atomic", "db.rpc",
    ...)` cobrindo `db.system=postgresql`, `db.operation=rpc:...`,
    `db.row_count`, `omni.was_idempotent`, `db.error_code`. Route handler
    agora ecoa `X-Trace-Id` no response — suporte/cliente pode quotar
    para incident response. Padrão a ser replicado nas demais rotas
    financeiras conforme priorização.

  ### Mobile (Flutter)

  - **`omni_runner/lib/core/http/traced_http_client.dart`** (novo): thin
    wrapper sobre Sentry `SentryHttpClient` (que compõe `TracingClient` +
    `BreadcrumbClient` + `FailedRequestClient`). API pública:
      * `TracedHttpClient()` — substitui `http.Client()` em first-party calls
      * `TracedHttpClient.currentTraceHeaders()` — `Map<String, String>`
        para uso em `SupabaseClient.functions.invoke(headers: ...)` e
        outros code paths que não usam `http.Client`
      * `defaultFirstPartyAllowlist` — regex de hosts auth (`*.supabase.co`,
        `omnirunner.app`, `*.omnirunner.app`, `omnirunner.com.br`,
        `localhost`, `127.0.0.1`).
    Allowlist é aplicada em `main.dart` via `options.tracePropagationTargets`.
    **Defesa-em-profundidade**: trace headers NUNCA vão para Strava,
    Asaas ou Google APIs (data hygiene + zero benefício pois ignoram o
    header). **+5 testes** verdes.

  - **`omni_runner/lib/main.dart`**: `SentryFlutter.init` agora restringe
    `tracePropagationTargets` ao allowlist defensivo (sem essa mudança,
    Sentry default era `['.*']` = TUDO).

  ### Documentação

  - **`docs/observability/TRACING.md`** (novo, ~400 linhas): runbook
    canônico cobrindo:
      * **TL;DR** — tabela de qual camada propaga o quê
      * **Por que existe** — métrica antes/depois (~25 min → < 2 min para
        triagem de "pagamento lento")
      * **Como achar trace_id** — 4 caminhos: header `X-Trace-Id`,
        log structured, audit_log SQL, Sentry → log pivot
      * **Como instrumentar novo código** — exemplos `withSpan` +
        atributos OTel + outbound fetch + Flutter `TracedHttpClient`
      * **Limites e custo** — sampling table (P1=100%, P4=0%),
        cardinalidade de atributos (NUNCA em `name`), regras PII
      * **Operação durante incidente** — runbooks para 3 cenários
      * **Limitações conhecidas** — edge functions sem auto-instrum
        ainda, Asaas webhooks chegam sem `sentry-trace`, pg_cron
        invisível, P4 sample 0% → trace ausente
      * **Checklist de PR** — gate para route handlers críticos

  ## Validação

  - **portal**: `tsc --noEmit` clean, `next lint` clean, `vitest` 842/842
    verde (50 dos quais novos para L20-03).
  - **omni_runner**: `flutter analyze` clean (0 issues), `flutter test
    test/core/http test/core/logging` 11/11 verde.

  ## Próximas ondas

  Wave 2: instrumentar edge functions Supabase (Sentry Deno SDK ou OTLP
  exporter manual). Hoje, chamadas portal → edge function aparecem como
  span único `http.client POST` sem visibilidade dentro da função.
---

# Achado
— Request do mobile → Portal `/api/distribute-coins` → Supabase RPC → possivelmente edge function → webhook → banco. Não havia trace_id correlacionado end-to-end.

# Risco / Impacto
— "Pagamento demorou 15 segundos" era impossível diagnosticar — mobile? network? portal? RPC? edge? Asaas? Triagem média de incidentes lentos: ~25 min (medido em 3 retros 2026-Q1). Com tracing: < 2 min (single click pelo trace_id no Sentry).

# Correção implementada
Ver bloco `note:` acima para detalhes completos. Resumo: bootstrap Next.js `instrumentation.ts` + façade `tracing.ts` (`withSpan`/`currentTraceId`/`traceparent`) + auto-injeção de `trace_id` em audit + logger + rota financeira de exemplo + Flutter `TracedHttpClient` com allowlist defensivo + runbook canônico de 400 linhas. 25 novos testes (17 portal/observability + 4 audit + 4 logger + 5 flutter http).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.3).
- `2026-04-17` — Corrigido em commit `0050d00` (feature; promovido para `fixed`).