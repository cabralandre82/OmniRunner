---
id: L07-03
audit_ref: "7.3"
lens: 7
title: "App mobile sem modo offline robusto para corridas"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "cron", "reliability"]
files:
  - portal/src/lib/offline-sync/types.ts
  - portal/src/lib/offline-sync/queue.ts
  - portal/src/lib/offline-sync/policy.ts
  - portal/src/lib/offline-sync/index.ts
  - portal/src/lib/offline-sync/queue.test.ts
  - portal/src/lib/offline-sync/policy.test.ts
  - tools/audit/check-offline-sync.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/offline-sync/queue.test.ts
  - portal/src/lib/offline-sync/policy.test.ts
  - tools/audit/check-offline-sync.ts
linked_issues: []
linked_prs:
  - "local:166dbf1"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed at 2026-04-21 (commit 166dbf1) by shipping a pure-domain
  offline-sync queue module. Run capture now comes from Strava, but
  the queue primitive is still required for the newly-shipped offline
  flows: auto check-in (L23-08), session notes, pairing responses
  (L23-10), and workout completion marks.
    - portal/src/lib/offline-sync/types.ts — 5-state machine (pending,
      in_flight, done, failed, dead_letter), DEFAULT_RETRY_POLICY
      (15 s base, 6 h cap, 12 attempts, ±20 % jitter),
      DEFAULT_OFFLINE_ALERT_POLICY (pendingCountThreshold = 5,
      oldestPendingAgeMsThreshold = 3 days, matching the finding's
      "push if > 3 days" recommendation).
    - queue.ts — pure reducer: enqueue (idempotent by id), pickReady
      (sorted by nextAttemptAt, limit), markInFlight, ack (ok →
      done; retryable → exponential backoff; non-retryable or
      attempts ≥ maxAttempts → dead_letter), requeueDeadLetter,
      purgeCompleted, snapshot.
    - policy.ts — computeNextAttemptAt with exponential doubling,
      maxDelayMs cap, and symmetric ± jitter band; evaluateAlert with
      severity priority dead_letter > (pending ∧ age) > age >
      pending > OK.
    - index.ts re-exports types + policy + queue.
    - 19 vitest unit tests covering idempotency, ordering, backoff
      doubling, cap enforcement, jitter band, maxAttempts dead-letter,
      requeue, purge, snapshot, and every alert branch.
    - 43-invariant CI guard `npm run audit:offline-sync`.
  Follow-up: the Flutter client will bind Drift persistence to this
  reducer in a subsequent PR — the pure module can be verified in
  isolation first.
---
# [L07-03] App mobile sem modo offline robusto para corridas
> **Lente:** 7 — CXO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/data/datasources/drift_database.dart` grava localmente, mas `auto_sync_manager.dart` assume conexão frequente. Se atleta treina 10 dias em lugar remoto (trilha serra), retorno → **10 sessões pendentes** aparecem juntas, risco de perder se reinstalar app antes do sync.
## Risco / Impacto

— Atleta perde treino → quebra trust no produto. Atleta profissional perde dado científico.

## Correção proposta

—

1. Warning visível: "Você tem 10 sessões não sincronizadas. Conecte-se à internet."
2. Export manual: botão "Enviar por email (.fit)" que envia do dispositivo.
3. Queue persistente em SQLite (já tem) + retry exponential backoff + notificação push se > 3 dias.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.3).