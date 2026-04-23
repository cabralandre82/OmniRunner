---
id: L07-04
audit_ref: "7.4"
lens: 7
title: "Flutter deep link Strava OAuth sem state validation (CSRF)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["integration", "mobile", "ux", "security", "csrf"]
files:
  - omni_runner/lib/features/strava/data/strava_oauth_state.dart
  - omni_runner/lib/features/strava/data/strava_auth_repository_impl.dart
  - omni_runner/lib/core/errors/integrations_failures.dart
  - omni_runner/lib/core/errors/strava_failures.dart
  - omni_runner/lib/core/deep_links/deep_link_handler.dart
  - omni_runner/lib/presentation/screens/settings_screen.dart
  - tools/audit/check-strava-oauth-state.ts
  - docs/runbooks/STRAVA_OAUTH_CSRF_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/features/strava/strava_oauth_state_test.dart
  - omni_runner/test/features/strava/strava_auth_repository_test.dart
linked_issues: []
linked_prs:
  - "89afcb8"
owner: mobile
runbook: docs/runbooks/STRAVA_OAUTH_CSRF_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "2026-04-21 — fixed. StravaOAuthStateGuard (32-byte CSPRNG, FlutterSecureStorage, 10-min TTL, constant-time compare, consume-once) wired into StravaAuthRepositoryImpl.authenticate() via _stateGuard.beginFlow() + validateAndConsume(returnedState). New OAuthCsrfViolation IntegrationFailure subclass with reason in {state_missing, state_mismatch} surfaced distinctly in settings_screen UX. Deep-link handler (L01-29) keeps rejecting legacy omnirunner://strava/callback paths as UnknownLinkAction. CI npm run audit:strava-oauth-state (17 checks) + runbook."
---
# [L07-04] Flutter deep link Strava OAuth sem state validation (CSRF)
> **Lente:** 7 — CXO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Já citado em PARTE 1 [1.20] — `omni_runner/lib/core/deep_links/deep_link_handler.dart`. Crítico UX também: atleta tenta conectar, é redirecionado de volta, o app abre mas **não confirma sucesso** porque state não é verificado. Comportamento indeterminado.
## Correção proposta

— Gerar `state = secureRandom(32)` antes do OAuth, armazenar em `FlutterSecureStorage`, verificar match no callback. UX: toast "Conectado ao Strava ✓" só quando state confere.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.4).
- `2026-04-21` — Corrigido. A defesa §10.12 estava em parte instalada via L01-29 (`StravaOAuthStateGuard` + `_stateGuard.beginFlow()` + `_stateGuard.validateAndConsume(returnedState)` em `StravaAuthRepositoryImpl.authenticate`) mas a falha caía em `AuthFailed('OAuth state mismatch')` e a UI tratava igual a erro de rede. Este PR (a) introduz `OAuthCsrfViolation` (final class em `integrations_failures.dart` com reason ∈ {state_missing, state_mismatch}), (b) troca o `throw` em `StravaAuthRepositoryImpl` para essa classe + log WARN específico, (c) re-export via `strava_failures.dart` barrel, (d) `settings_screen.dart` pattern-matcheia antes do catch genérico e mostra mensagem user-safe tingida com `colorScheme.error` ("Tentativa de conexão inválida detectada" / "Retorno do Strava sem verificação de segurança"), (e) CI `npm run audit:strava-oauth-state` com 17 regressions (guard primitives + repo wiring + failure export + deep-link denial + test coverage + UX pattern-match), (f) runbook canônico `docs/runbooks/STRAVA_OAUTH_CSRF_RUNBOOK.md` cobrindo arquitetura, reasons, 5 cenários operacionais (spike em Crashlytics, suporte L1, tighten TTL, adicionar segundo provider, legacy callback re-aparecer) + invariantes. 41/41 flutter tests verdes. Deep-link handler continua rejeitando `omnirunner://strava/callback` (L01-29).