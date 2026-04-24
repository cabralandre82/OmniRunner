---
id: L01-28
audit_ref: "1.28"
lens: 1
title: "Deep link handler — extractInviteCode aceita qualquer string"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["rate-limit", "mobile", "ux", "seo", "fixed"]
files:
  - omni_runner/lib/core/deep_links/deep_link_handler.dart
  - omni_runner/test/core/deep_links/deep_link_handler_test.dart
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - "omni_runner/test/core/deep_links/deep_link_handler_test.dart (4 new L01-28 cases)"
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
  K3 batch — DeepLinkHandler.extractInviteCode now validates with
  RegExp(r'^[A-Z0-9_-]{6,16}$') for both URL-extracted and raw inputs.
  Random QR text ('BUY BITCOIN'), lowercase strings, too-short and
  too-long codes are now rejected client-side; the backend is no
  longer hit with doomed lookups (rate-limit + UX win).
---
# [L01-28] Deep link handler — extractInviteCode aceita qualquer string
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** APP (Flutter)
**Personas impactadas:** Atleta
## Achado
`omni_runner/lib/core/deep_links/deep_link_handler.dart:195` retorna `trimmed` como código se for não-vazio e não contém `/`. Não valida tamanho, charset, formato. Um QR code com texto aleatório (ex: "BUY BITCOIN") vira um convite inválido que vai até o backend.
## Risco / Impacto

Consumo desnecessário de backend (rate limit), confusão UX.

## Correção proposta

```dart
  static final _codeFormat = RegExp(r'^[A-Z0-9]{6,16}$');
  static String? extractInviteCode(String input) {
    final trimmed = input.trim();
    // URL path extraction...
    if (_codeFormat.hasMatch(trimmed)) return trimmed;
    return null;
  }
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.28]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.28).