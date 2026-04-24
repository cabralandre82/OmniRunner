---
id: L01-32
audit_ref: "1.32"
lens: 1
title: "Flutter — flutter_secure_storage sem setSharedPreferences"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "a11y", "reliability", "secure-storage", "fixed"]
files:
  - omni_runner/lib/core/secure_storage/db_secure_store.dart
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: mobile
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — DbSecureStore now defaults to a hardened storage
  configuration:
    AndroidOptions(encryptedSharedPreferences: true)
    IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)
  No more silent fallback to SharedPreferences plain on Android; on
  iOS the key is excluded from iCloud Keychain backups while staying
  available after first unlock. Tests still inject a fake storage
  via the constructor parameter for unit testing.
---
# [L01-32] Flutter — flutter_secure_storage sem setSharedPreferences
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** APP (Flutter)
**Personas impactadas:** Atleta, Staff
## Achado
`db_secure_store.dart:22-24` usa `FlutterSecureStorage()` com opções default. No Android, sem opções explícitas, usa EncryptedSharedPreferences; se não estiver disponível (APIs < 23 em devices antigos), fallback inseguro para SharedPreferences plain.
## Risco / Impacto

minSdkVersion é 26 (ok), mas para iOS, sem `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`, a key fica acessível mesmo com device bloqueado (comportamento padrão é `KeychainAccessibility.unlocked`, mais restritivo na verdade). Ainda assim, explicitar é melhor.

## Correção proposta

```dart
  const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.32]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.32).