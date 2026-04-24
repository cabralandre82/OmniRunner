---
id: L01-33
audit_ref: "1.33"
lens: 1
title: "Flutter — DB key storage fallback ausente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "reliability", "secure-storage", "fixed"]
files:
  - omni_runner/lib/core/secure_storage/db_secure_store.dart
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - e022472
  - 908a5b7
  - 9fc89cc
owner: mobile
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — DbSecureStore.getOrCreateKey now uses a _safeRead helper
  that catches PlatformException from flutter_secure_storage. On
  irrecoverable corruption (e.g., user wiped the keystore, vendor
  ROM mishandled the keystore migration, biometric reset) we:
    1) regenerate a fresh 32-byte AES key,
    2) write it back to secure storage, and
    3) delete the on-disk SQLCipher database so it can be reopened
       under the new key (data was unrecoverable anyway).
  The app launches successfully instead of crash-looping at startup.
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