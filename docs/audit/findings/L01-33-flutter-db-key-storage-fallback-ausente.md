---
id: L01-33
audit_ref: "1.33"
lens: 1
title: "Flutter — DB key storage fallback ausente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "reliability"]
files: []
correction_type: process
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
# [L01-33] Flutter — DB key storage fallback ausente
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** APP
**Personas impactadas:** Atleta
## Achado
`db_secure_store.dart:29-51`: se `flutter_secure_storage.read` **lançar exceção** (ex: keystore corrompido no Android), não há handler — crash. Usuário perde acesso ao app até reinstalar.
## Correção proposta

Try/catch com fallback para `clearKeyAndDatabase()` + re-geração de key (perdendo dados locais, mas app volta a funcionar):
  ```dart
  try {
    existing = await _storage.read(...);
  } on PlatformException catch (e) {
    AppLogger.error('Secure storage corrupted, regenerating', tag: _tag, error: e);
    await clearKeyAndDatabase();
    existing = null;
  }
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.33]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.33).