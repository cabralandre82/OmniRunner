---
id: L07-03
audit_ref: "7.3"
lens: 7
title: "App mobile sem modo offline robusto para corridas"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "cron", "reliability"]
files:
  - omni_runner/lib/data/datasources/drift_database.dart
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