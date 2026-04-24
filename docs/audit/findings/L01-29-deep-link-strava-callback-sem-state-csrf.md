---
id: L01-29
audit_ref: "1.29"
lens: 1
title: "Deep link — Strava callback sem state/CSRF"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["security-headers", "integration", "mobile", "seo", "reliability"]
files:
  - "omni_runner/lib/features/strava/data/strava_oauth_state.dart"
  - "omni_runner/lib/features/strava/data/strava_auth_repository_impl.dart"
  - "omni_runner/lib/features/strava/data/strava_http_client.dart"
  - "omni_runner/lib/core/deep_links/deep_link_handler.dart"
  - "omni_runner/lib/core/di/data_module.dart"
  - "omni_runner/lib/presentation/screens/auth_gate.dart"
correction_type: code
test_required: true
tests:
  - omni_runner/test/features/strava/strava_oauth_state_test.dart
  - omni_runner/test/features/strava/strava_auth_repository_test.dart
  - omni_runner/test/core/deep_links/deep_link_handler_test.dart
linked_issues: []
linked_prs:
  - "commit:396340c"
owner: app-team
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed by a three-layer defence (commit `396340c`):

  1. **`StravaOAuthStateGuard`** (new) mints a 32-byte CSPRNG token
     base64url-encoded per OAuth flow, persists it to secure_storage
     with a 10-minute TTL and absolute expiry timestamp. The guard is
     decoupled from `FlutterSecureStorage` via a small
     `OAuthStateStorage` interface so unit tests run without the
     platform channel. `validateAndConsume()` compares the returned
     value in constant time, clears storage on every path
     (success/mismatch/expired/missing), and enforces consume-once
     semantics — replaying the same `state` on a second callback
     fails by design.

  2. **`StravaAuthRepositoryImpl.authenticate()`** now calls
     `beginFlow()` BEFORE building the auth URL, threads the token
     into the `state=` query param via the updated
     `StravaHttpClient.buildAuthorizationUrl`, and runs
     `validateAndConsume(returnedState)` BEFORE inspecting the
     `code` parameter. A mismatch raises
     `AuthFailed("OAuth state mismatch — flow aborted")` and the
     token exchange never happens. State is cleared on every
     cancel/error branch (PlatformException, IntegrationFailure,
     AuthCancelled, generic Exception). The `FlutterWebAuth2.authenticate`
     call was extracted behind a `WebAuthLauncher` typedef so the
     happy/mismatch/replay/cancel branches are testable end-to-end
     without binding to the real platform channel.

  3. **`DeepLinkHandler`** legacy Strava callback parsing branches
     (`omnirunner://strava/callback?code=X` and
     `omnirunner://localhost/exchange_token?code=X`) were REMOVED.
     Production OAuth runs only through `flutter_web_auth_2` on the
     dedicated `omnirunnerauth://` scheme — these `omnirunner://`
     branches were dead code that any future consumer could
     accidentally re-enable to inherit the original CSRF. Inbound
     forged links now classify as `UnknownLinkAction` and are
     ignored. The `StravaCallbackAction` class itself is kept as
     `@deprecated` to preserve the defensive guard in
     `auth_gate._onDeepLink` that warns if any code path reintroduces
     the action.

  Tests (56 cases passing across three suites):
  - `strava_oauth_state_test.dart` — 16 cases covering token
    minting, CSPRNG uniqueness, single-in-flight overwrite, TTL
    expiry, mismatch, replay, missing/empty/null returned state,
    storage corruption, and clear semantics.
  - `strava_auth_repository_test.dart` — 6 new cases for the
    `authenticate()` flow: happy path with state match + token
    exchange, forged callback rejection, missing state in callback,
    replay across two flows, URL embeds the minted state, and state
    cleared on cancellation.
  - `deep_link_handler_test.dart` — 3 updated cases asserting the
    legacy paths now return `UnknownLinkAction` (with and without a
    state param).
---
# [L01-29] Deep link — Strava callback sem state/CSRF
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** APP (Flutter)
**Personas impactadas:** Atleta (linkando Strava)
## Achado
`deep_link_handler.dart:142-147` aceitava `code` do Strava OAuth callback **sem validar parâmetro `state`**. Padrão OAuth 2.0 exige `state` para CSRF protection.
## Risco / Impacto

Atacante induz vítima a autorizar o Strava do atacante na conta Omni Runner da vítima (login CSRF) — a conta Strava do atacante fica vinculada à vítima, que passa a ver atividades do atacante como suas.

## Correção aplicada

Ver `note` no frontmatter — três camadas (CSPRNG state guard + validação no repo + remoção dos paths legados).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.29]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.29).
- `2026-04-17` — Promovido a `fixed` (commit `396340c`). State CSPRNG +
  consume-once defence implementada em `StravaOAuthStateGuard`,
  validação adicionada em `StravaAuthRepositoryImpl.authenticate()`
  antes do token exchange, e branches legados de deep-link
  (`omnirunner://strava/...`, `omnirunner://localhost/exchange_token`)
  removidos para fechar a superfície de ataque por completo.