---
id: L08-02
audit_ref: "8.2"
lens: 8
title: "product_events.properties jsonb aceita qualquer payload — PII leak risk"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["lgpd", "rls", "mobile"]
files:
  - supabase/migrations/20260421100000_l08_product_events_hardening.sql
  - omni_runner/lib/core/analytics/product_event_tracker.dart
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
  Fixed in the same commit as L08-01 — both target
  `public.product_events`, both share the same defence stack.

  Architecture (3 layers of defence):

  1. **Postgres trigger `trg_validate_product_event` BEFORE INSERT
     OR UPDATE** — calls `fn_validate_product_event()` which raises
     SQLSTATE PE001..PE005 for invalid payloads. This is the
     CANONICAL enforcement point — uniformly applied to mobile
     (supabase_flutter), portal (supabase-js), and any future
     ingestion path (Edge Function, batch importer). Validates:
       • PE001 — `event_name` ∈ whitelist (8 names today)
       • PE002 — every property key ∈ whitelist (18 keys today)
       • PE003 — every property value is primitive
         (string/number/boolean/null) — no nested objects/arrays
         (closes the "shove the entire profile/run object into
         properties" smuggling vector)
       • PE004 — string values ≤ 200 chars
       • PE005 — `properties` is a JSON object (not array/scalar)

  2. **Client-side mirrors** — Dart (`ProductEvents.validate`) and
     TS (`validateProductEvent` in
     `portal/src/lib/product-event-schema.ts`) replicate the same
     whitelist. They drop invalid events with a console warn instead
     of round-tripping a doomed insert. Cross-language drift is
     detected by `tools/test_l08_01_02_product_events_hardening.ts`
     ("Cross-language whitelist parity" section).

  3. **Runbook** — `docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md` documents
     the 4-place workflow for adding a new event/key, the LGPD
     incident response (purge query + ANPD notification thresholds),
     and the trigger-disabled drill.

  Verification:

  - All 5 SQLSTATEs (PE001..PE005) covered by:
      • Migration self-test (in-TX before commit)
      • `tools/test_l08_01_02_product_events_hardening.ts` (live)
      • `portal/src/lib/analytics.test.ts` (unit)
      • `omni_runner/test/core/analytics/product_event_tracker_test.dart`
        (unit)
  - Happy path: every (event_name, key) pair currently emitted by
    mobile + portal is asserted to PASS validation in all three
    test layers.
---
# [L08-02] product_events.properties jsonb aceita qualquer payload — PII leak risk
> **Lente:** 8 — CDO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** database + mobile + portal (analytics)
**Personas impactadas:** DPO/Privacy (LGPD compliance), CDO (BI export sanity), todos os usuários (não-leak de dados)

## Achado

A coluna `public.product_events.properties` era `jsonb NOT NULL DEFAULT '{}'` sem validação — qualquer payload era aceito. Combinado com o pattern de chamada do Dart (`track("session_submitted", {"pace": 5.3, "location": sessionLatLng})`), nada impedia um dev distraído de fazer:

```dart
tracker.track('flow_abandoned', {
  'email': user.email,
  'cpf': profile.cpf,
  'polyline': encodePolyline(currentRun.points),
});
```

E como a tabela `product_events` tem RLS policy `product_events_staff_read` que dá `SELECT` para `admin_master` / `professor` da assessoria do atleta, e como o pipeline de export para BI/marketing roda com service role, o blast radius é amplo.

## Risco / Impacto

- **Violação LGPD** em produto de analytics distribuído a stakeholders de marketing/BI internos e potencialmente parceiros.
- **Multa ANPD** — vazamento de PII (CPF/email/localização) em base não-justificada por finalidade legítima ≠ "analytics de produto".
- **Reputational** — o público alvo do app são corredores conscientes; vazamento de polyline (ou seja, residência habitual) é particularmente grave.
- **Detecção difícil** — nenhum red-flag automático antes do scan trimestral; a primeira evidência costuma ser um relatório DPO ou um cliente reclamando que viu seu nome em dashboard.

## Correção implementada

Ver `note` no front-matter. Resumo:

1. Trigger `trg_validate_product_event` BEFORE INSERT OR UPDATE em `public.product_events` rejeita 5 classes de payload inválido (PE001..PE005).
2. Dart `ProductEvents.validate` e TS `validateProductEvent` replicam o whitelist; drop-and-warn em vez de insert.
3. Runbook `docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md` documenta o workflow de adicionar nova key (revisão obrigatória de Privacy/DPO).

## Teste de regressão

- `tools/test_l08_01_02_product_events_hardening.ts` — todos os 5 SQLSTATEs PE001..PE005, happy path, cross-language parity.
- `portal/src/lib/analytics.test.ts` — drop-and-warn TS com mensagens explícitas.
- `omni_runner/test/core/analytics/product_event_tracker_test.dart` — drop-and-warn Dart, todas as call sites reais validadas.
- Migration self-test em `supabase/migrations/20260421100000_l08_product_events_hardening.sql`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.2).
- `2026-04-21` — ✅ Fix completo: trigger Postgres + client-side mirrors + runbook (junto com L08-01).
