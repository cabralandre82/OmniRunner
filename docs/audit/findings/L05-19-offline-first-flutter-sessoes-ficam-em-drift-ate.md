---
id: L05-19
audit_ref: "5.19"
lens: 5
title: "Offline-first Flutter: sessões ficam em drift até sincronizar"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "cron", "reliability"]
files: []
correction_type: config
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-19] Offline-first Flutter: sessões ficam em drift até sincronizar
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `drift_database.dart` salva sessões localmente. Se atleta corre, não sincroniza, troca de celular → perde treino.
## Correção proposta

— Backup local em `FlutterSecureStorage` ou botão "Enviar por email todas as corridas pendentes".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.19).