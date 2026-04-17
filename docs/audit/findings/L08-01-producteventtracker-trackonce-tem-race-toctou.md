---
id: L08-01
audit_ref: "8.1"
lens: 8
title: "ProductEventTracker.trackOnce tem race TOCTOU"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "ux", "performance", "testing"]
files:
  - omni_runner/lib/core/analytics/product_event_tracker.dart
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
# [L08-01] ProductEventTracker.trackOnce tem race TOCTOU
> **Lente:** 8 — CDO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/core/analytics/product_event_tracker.dart:60-78`:

```60:78:omni_runner/lib/core/analytics/product_event_tracker.dart
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

Se duas chamadas concorrentes ocorrem (ex: conexão instável, double-tap, sync ao voltar online): ambas leem empty, ambas inserem → **`first_challenge_created` registrado 2 vezes**.
## Risco / Impacto

— Métricas de funil **infladas** → decisões de produto erradas. "70 % dos usuários concluíram onboarding" pode ser 50 %.

## Correção proposta

— Índice único + upsert:

```sql
CREATE UNIQUE INDEX idx_product_events_once
  ON product_events(user_id, event_name)
  WHERE event_name LIKE 'first_%' OR event_name = 'onboarding_completed';
```

```dart
await sl<SupabaseClient>().from(_table).upsert({
  'user_id': uid, 'event_name': eventName, 'properties': properties ?? {}
}, onConflict: 'user_id,event_name', ignoreDuplicates: true);
```

## Teste de regressão

— `product_events_once.test.dart`: 10 chamadas paralelas para o mesmo `first_*` → `SELECT COUNT(*)` == 1.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.1).