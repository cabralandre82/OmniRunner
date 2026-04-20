---
id: L08-01
audit_ref: "8.1"
lens: 8
title: "ProductEventTracker.trackOnce tem race TOCTOU"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "ux", "performance", "testing"]
files:
  - omni_runner/lib/core/analytics/product_event_tracker.dart
  - supabase/migrations/20260421100000_l08_product_events_hardening.sql
  - portal/src/lib/analytics.ts
  - portal/src/lib/product-event-schema.ts
  - docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/core/analytics/product_event_tracker_test.dart
  - portal/src/lib/analytics.test.ts
  - tools/test_l08_01_02_product_events_hardening.ts
linked_issues: []
linked_prs: ["9c2cc88"]
owner: platform
runbook: docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fix delivered alongside L08-02 (PII leak via free-form jsonb) since
  both target `public.product_events` and a shared validator trigger
  was the natural canonical defence.

  Architecture (3 layers):

  1. **Database — `idx_product_events_user_event_once`** (UNIQUE
     PARTIAL INDEX on `(user_id, event_name)` WHERE
     `event_name LIKE 'first_%' OR event_name = 'onboarding_completed'`).
     Concurrent inserts of the same one-shot event for the same user
     collapse into a single row via SQLSTATE 23505 — net DB state is
     always 1 row per user/event. Multi-shot events (`flow_abandoned`,
     `billing_*`) intentionally fall outside the predicate so they
     stay countable.

  2. **Mobile — `ProductEventTracker.trackOnce`** now issues a plain
     `insert` and silently swallows `PostgrestException` with
     `code == '23505'` for one-shot events. We could not use
     `upsert(ignoreDuplicates: true)` because PostgREST cannot attach
     a partial-index predicate to the `ON CONFLICT` clause — the
     swallow-23505 pattern reaches the same end-state with fewer
     moving parts.

  3. **Documentation — `docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md`**
     covers the "add a new one-shot event" workflow (predicate
     extension), the de-dup script for historical TOCTOU damage,
     and the "regression in client" bisecte.

  Verification:

  - `tools/test_l08_01_02_product_events_hardening.ts` test
    "20 concurrent inserts collapse to 1 row via partial unique
    index (TOCTOU killed)" — exactly 1 success, 19 unique-violations,
    0 other errors, final DB state = 1 row.
  - Migration self-test (in-TX `DO ... $self_test$`) covers the
    same path before commit.
  - Dart unit tests cover the dispatch/swallow side with a recording
    fake Supabase client.
---
# [L08-01] ProductEventTracker.trackOnce tem race TOCTOU
> **Lente:** 8 — CDO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** mobile + database + portal (analytics)
**Personas impactadas:** Product/CDO (decisões de funil), Engenharia (depuração de métricas infladas)

## Achado

Implementação original em `omni_runner/lib/core/analytics/product_event_tracker.dart:60-78` (pré-fix):

```dart
final existing = await sl<SupabaseClient>()
    .from(_table)
    .select('id')
    .eq('user_id', uid)
    .eq('event_name', eventName)
    .limit(1);

if ((existing as List).isNotEmpty) { … return; }

await sl<SupabaseClient>().from(_table).insert({
  'user_id': uid,
  'event_name': eventName,
  'properties': properties ?? {},
});
```

Padrão clássico TOCTOU — o `select` e o `insert` são dois round-trips separados. Duas chamadas concorrentes (double-tap, conexão instável + retry, sync ao voltar online) podem ambas ler `empty` e ambas inserir. Resultado: `first_challenge_created` registrado 2× (ou 10×, em casos extremos com fila offline).

## Risco / Impacto

- **Métricas de funil infladas.** "70% dos usuários concluíram onboarding" pode ser 50% real → decisões de produto erradas (gastar engenharia consertando um onboarding que já está bom, ou ignorar um drop-off real porque a métrica esconde).
- **Análises de coorte erradas.** Coortes calculadas por `MIN(created_at) WHERE event_name='first_*'` ficam compatíveis, mas qualquer agregação `COUNT(*) GROUP BY event_name` fica inflada e contradiz totalizadores.
- **Custo de armazenamento.** Em si trivial (eventos são leves), mas multiplica por tabela jsonb que cresce linearmente.

## Correção implementada

Ver `note` no front-matter. Resumo: unique partial index no Postgres + plain insert + swallow 23505 no Dart + integration test que injeta 20 inserts concorrentes e prova final state = 1 row.

## Teste de regressão

- `tools/test_l08_01_02_product_events_hardening.ts` — "20 concurrent inserts collapse to 1 row".
- `omni_runner/test/core/analytics/product_event_tracker_test.dart` — "10 concurrent trackOnce calls all dispatch (DB enforces uniqueness)".
- Migration self-test em `supabase/migrations/20260421100000_l08_product_events_hardening.sql`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.1).
- `2026-04-21` — ✅ Fix completo: unique partial index + Dart 23505-swallow + integration test (junto com L08-02).
