---
id: L01-29
audit_ref: "1.29"
lens: 1
title: "Deep link — Strava callback sem state/CSRF"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["security-headers", "integration", "mobile", "seo", "reliability"]
files: []
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
# [L01-29] Deep link — Strava callback sem state/CSRF
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** APP (Flutter)
**Personas impactadas:** Atleta (linkando Strava)
## Achado
`deep_link_handler.dart:142-147` aceita `code` do Strava OAuth callback **sem validar parâmetro `state`**. Padrão OAuth 2.0 exige `state` para CSRF protection.
## Risco / Impacto

Atacante induz vítima a autorizar o Strava do atacante na conta Omni Runner da vítima (login CSRF) — a conta Strava do atacante fica vinculada à vítima, que passa a ver atividades do atacante como suas.

## Correção proposta

Gerar `state = base64(csprng)` antes do redirect OAuth, armazenar em secure_storage, e validar no callback:
  ```dart
  if (uri.scheme == 'omnirunner' && (isExchangeToken || isLegacy)) {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final expected = await secureStorage.read(key: 'strava_oauth_state');
    if (state == null || state != expected) return UnknownLinkAction(uri);
    await secureStorage.delete(key: 'strava_oauth_state');
    return StravaCallbackAction(code!);
  }
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.29]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.29).