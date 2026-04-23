---
id: L11-05
audit_ref: "11.5"
lens: 11
title: "flutter_secure_storage: ^10.0.0 mas release inclui shared_preferences"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "security", "supply-chain", "lint", "storage"]
files:
  - omni_runner/lib/core/storage/preferences_keys.dart
  - omni_runner/lib/core/storage/prefs_safe_key.dart
  - tools/audit/check-shared-prefs-sensitive-keys.ts
correction_type: lint
test_required: true
tests:
  - omni_runner/test/core/storage/preferences_keys_test.dart
linked_issues: []
linked_prs:
  - "local/aaf0277 — fix(mobile): SharedPreferences sensitive-key lint + safe-key wrapper (L11-05)"
owner: mobile
runbook: docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Landed 2026-04-21 with three defensive layers instead of a single custom_lint
  package (which is 2–3 days of yak-shaving per-dev for marginal gain):

  LAYER 1 — CATALOGUE (lib/core/storage/preferences_keys.dart + prefs_safe_key.dart)
  • PreferencesKeys is the SINGLE allowed entry point for the SharedPreferences
    keyspace. Every entry routes through PrefsSafeKey.plain(...) or .prefix(...),
    which run assertSafe(name) at class-load time (app boot).
  • Heuristic (case-insensitive, underscore/hyphen aware):
      tokens?|secret|password|credential|api[_-]?key|auth[_-]?(token|secret|code)
      |private[_-]?key|refresh[_-]?token|access[_-]?token|jwt|bearer
      |session[_-]?(id|token|secret)|oauth[_-]?(state|token|secret)
      |mfa[_-]?(code|secret)|otp[_-]?(code|secret)?|pin[_-]?(code|hash)
      |cvv|card[_-]?number|ssn|cpf|passport|totp[_-]?secret
  • Custom boundary (?<![a-zA-Z])...(?![a-zA-Z]) fixes Dart's \b-over-underscore
    problem: matches access_token AND my_access_token, still rejects tokenize.
  • Explicit allowlist: strava_athlete_name, strava_athlete_id (public profile).
  • PrefsSafeKeyViolation (ArgumentError) thrown at boot — crashes loudly; a
    secret in plaintext is data-loss class, not log-and-continue.

  LAYER 2 — FLUTTER TEST (test/core/storage/preferences_keys_test.dart, 9 tests)
  • 28 sensitive keywords correctly rejected.
  • 21 safe keys correctly accepted.
  • Allowlist honored for strava_athlete_name/id.
  • Error message carries L11-05 id + FlutterSecureStorage pointer.
  • Every PreferencesKeys.allKeys entry passes assertSafe.
  • No duplicates; every entry has purpose > 8 chars; prefixes end in '_'.

  LAYER 3 — CI GUARD (tools/audit/check-shared-prefs-sensitive-keys.ts)
  • npm run audit:shared-prefs-sensitive-keys.
  • Scans 891 .dart files under omni_runner/lib/** + test/** (minus guard files).
  • Three key-extraction modes: string literal, PreferencesKeys.<name>
    (camelCase→snake), bare identifier (camelCase→snake; variable named
    accessToken triggers even without a literal value).
  • Receivers recognised: prefs, sharedPrefs, _prefs, p, sp, _pref,
    sharedPreferences.
  • Opt-out: // L11-05-OK: <reason> on offending line or preceding line;
    every opt-out surfaced in report for reviewer audit.
  • Self-check: verifies preferences_keys.dart still imports prefs_safe_key.dart
    and still references PrefsSafeKey.plain/prefix/allKeys.

  Current tree: 0 violations, 0 opt-outs. Smoke tested with 3 planted
  violations (literal, camelCase var, PreferencesKeys-style) — all 3 flagged
  with correct file/line/pattern; planted opt-out surfaced the reason in
  report and suppressed the violation.

  RUNBOOK (docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md)
  • Policy decision table (what goes where, what is transient-only).
  • How to add a new key (5 steps).
  • How to add a new FlutterSecureStorage component (conventions, testing).
  • 6 operational playbooks (leak discovered; CI guard failed; Dart test
    failed; PrefsSafeKeyViolation at boot; false positive remediation;
    dependency-bump audit checklist).
  • Detection signals table.
  • Cross-refs to L01-29 (Strava OAuth state), L04-07, L10-09, L11-06/07/08,
    L01-30/31.

  flutter analyze: clean. flutter test: 2128 tests pass (9 new + 2119 existing).
---
# [L11-05] flutter_secure_storage: ^10.0.0 mas release inclui shared_preferences
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** —
**Personas impactadas:** —
## Achado
— `pubspec.yaml:63,55` declara `flutter_secure_storage: ^10.0.0` e `shared_preferences: ^2.5.4`. Auditoria anterior em [1.1] já identifica uso. Risco: devs confundem qual storage usar para dados sensíveis.
## Correção proposta

— Lint rule custom proibindo `shared_preferences` para chaves contendo `token|key|secret|auth` via `custom_lint` package.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.5).
- `2026-04-21` — ✅ **Fixed** (commit `aaf0277`). Três camadas defensivas: (1) **Catálogo** — `PreferencesKeys` refatorada para ser ÚNICO entry point do keyspace SharedPreferences; cada entrada passa por `PrefsSafeKey.plain`/`.prefix` que invoca `assertSafe(name)` em class-load (app boot). Heurística case-insensitive reject `tokens?/secret/password/credential/api[_-]?key/auth[_-]?(token|secret|code)/private[_-]?key/refresh[_-]?token/access[_-]?token/jwt/bearer/session[_-]?(id|token|secret)/oauth[_-]?(state|token|secret)/mfa[_-]?(code|secret)/otp[_-]?(code|secret)?/pin[_-]?(code|hash)/cvv/card[_-]?number/ssn/cpf/passport/totp[_-]?secret`. Custom boundary `(?<![a-zA-Z])...(?![a-zA-Z])` corrige limitação do Dart `\b` que não funciona em `_` — matches `access_token` E `my_access_token` sem matchar `tokenize`. Allowlist explícita: `strava_athlete_name`, `strava_athlete_id` (metadata pública). Violação lança `PrefsSafeKeyViolation` (ArgumentError) — crasha boot loud, secret em plaintext é data-loss class não log-and-continue. (2) **Dart test** (`test/core/storage/preferences_keys_test.dart`, 9 tests): 28 keywords sensíveis rejeitados + 21 keys safe aceitos + allowlist honrada + erro carrega L11-05 id + `FlutterSecureStorage` pointer; cada `PreferencesKeys.allKeys` entry passa assertSafe, sem duplicatas, purpose > 8 chars, prefixes terminam `_`. (3) **CI guard** `npm run audit:shared-prefs-sensitive-keys` (`tools/audit/check-shared-prefs-sensitive-keys.ts`): scan 891 `.dart` files em `omni_runner/lib/**` + `test/**` (menos guard files); 3 modos extração (string literal, `PreferencesKeys.<name>` camelCase→snake, bare identifier camelCase→snake — var `accessToken` flaggada mesmo sem literal); receivers `prefs/sharedPrefs/_prefs/p/sp/_pref/sharedPreferences`; opt-out `// L11-05-OK: <reason>` surface no report. Self-check: verifica `preferences_keys.dart` ainda importa `prefs_safe_key.dart` e referencia `PrefsSafeKey.plain/prefix/allKeys`. Tree atual: 0 violações, 0 opt-outs. Smoke-testado com 3 violações plantadas (literal string, camelCase var, `PreferencesKeys.<name>`) — todas flaggadas com file:line:pattern; opt-out plantado surface reason e suprime violação. **Runbook** `docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md`: policy table (o que usa `FlutterSecureStorage` vs `SharedPreferences` vs neither), 5-step add-new-key, convenção para novo `FlutterSecureStorage` component, 6 operational playbooks (leak discovered → migration block pattern + forced token refresh; CI guard failed; Dart test failed; `PrefsSafeKeyViolation` at boot; false positive remediation; dependency-bump audit checklist), detection signals, cross-refs (L01-29 Strava OAuth, L04-07 PII, L10-09 credential stuffing, L11-06/07/08 supply chain siblings, L01-30/31 release hardening). Decisão arquitetural: o finding original sugeria `custom_lint` package — preferimos 3 defense layers + assertSafe em boot porque (a) custom_lint exige package dedicado + `dart run custom_lint` separado por dev, (b) boot-time assert cobre 100% dos paths mesmo quando dev esquece de rodar lint local, (c) CI guard cobre call-sites fora do catálogo (literal strings em features). **Testes**: `flutter analyze` clean, `flutter test` passa 2128 tests (9 novos + 2119 existentes). Zero regressão.