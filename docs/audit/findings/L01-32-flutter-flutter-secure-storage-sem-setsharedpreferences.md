---
id: L01-32
audit_ref: "1.32"
lens: 1
title: "Flutter — flutter_secure_storage sem setSharedPreferences"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "a11y", "reliability"]
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