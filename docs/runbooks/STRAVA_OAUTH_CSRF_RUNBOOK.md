# Strava OAuth — CSRF `state` Runbook (L07-04)

> **Audience**: mobile engineers, SRE, support  
> **Audit finding**: [L07-04](../audit/findings/L07-04-flutter-deep-link-strava-oauth-sem-state-validation.md)  
> **Cross-refs**: [L01-29](../audit/findings/L01-29-ios-universal-link-sem-verificacao-do-apple-app-site-associa.md), [L10-07](./JWT_ZERO_TRUST_RUNBOOK.md)  
> **Scope**: the Flutter OAuth 2.0 flow to `https://www.strava.com/oauth/authorize`, callback on `omnirunnerauth://localhost/exchange_token`.

---

## 1. Why this exists

Strava is the **single source of truth** for activity data — GPS streams,
heart rate, cadence, moving time — and drives anti-cheat, challenge
progress, and ranking. A successful login-CSRF against the OAuth flow
would graft an **attacker-controlled Strava account** onto the victim's
Omni Runner profile. The attacker's activities would then surface as the
victim's runs and:

- contaminate anti-cheat baselines (`fn_get_anti_cheat_thresholds`),
- pollute rankings and challenge leaderboards,
- create a regulatory trail (LGPD) where activity data crosses users.

RFC 6749 §10.12 is explicit: clients **MUST** send an opaque,
non-guessable `state` parameter to the authorization server and **MUST**
reject any callback whose echoed `state` does not match. `flutter_web_auth_2`
gives us some implicit isolation at the OS layer, but `state` is the
contract-level defence and the one we own end-to-end.

---

## 2. What shipped

| Piece | File | Responsibility |
|---|---|---|
| **CSPRNG state guard** | `omni_runner/lib/features/strava/data/strava_oauth_state.dart` | `StravaOAuthStateGuard`: 32-byte `Random.secure()` tokens, `FlutterSecureStorage` persistence, TTL 10 min, constant-time compare, consume-once |
| **Repo wiring** | `omni_runner/lib/features/strava/data/strava_auth_repository_impl.dart` | `authenticate()` calls `beginFlow()` → embeds in auth URL → validates via `validateAndConsume(returnedState)` BEFORE any token exchange |
| **Typed failure** | `omni_runner/lib/core/errors/integrations_failures.dart` | `OAuthCsrfViolation(reason)` with machine-readable reason in `{state_missing, state_mismatch}` |
| **Dedicated UX** | `omni_runner/lib/presentation/screens/settings_screen.dart` | pattern-matches `OAuthCsrfViolation` ahead of the generic `IntegrationFailure` catch and surfaces a user-safe error snackbar tinted with `colorScheme.error` |
| **Deep-link denial** | `omni_runner/lib/core/deep_links/deep_link_handler.dart` | legacy `omnirunner://strava/callback` and `omnirunner://localhost/exchange_token` paths are returned as `UnknownLinkAction` (L01-29) |
| **CI guard** | `tools/audit/check-strava-oauth-state.ts`, `npm run audit:strava-oauth-state` | 17 regressions covering the guard primitives, repo wiring, failure export, deep-link rejection, test coverage, and UX pattern-match |
| **Unit tests** | `omni_runner/test/features/strava/strava_oauth_state_test.dart`, `omni_runner/test/features/strava/strava_auth_repository_test.dart` | 16 state-guard tests + 6 CSRF repository integration tests (happy path, mismatch, missing, replay, authorize URL embeds state, cancellation clears state) |

### 2.1. Lifecycle

```
                            ┌──────────────────────────────────────┐
                            │       User taps "Conectar Strava"    │
                            └──────────────────────────────────────┘
                                              │
                                              ▼
              beginFlow()  ──►  secureRandom(32B) → base64url token
                                 FlutterSecureStorage.write(token, now+10min)
                                 return token
                                              │
                                              ▼
                       buildAuthorizationUrl(state=token)
                                              │
                                              ▼
                   flutter_web_auth_2.authenticate(url, omnirunnerauth)
                                              │
                                              ▼
                       Strava redirects → omnirunnerauth://…?code=X&state=Y
                                              │
                                              ▼
   validateAndConsume(Y)   ──►   Y==token AND not expired?
                                     │ yes → true  (storage cleared)
                                     │ no  → false (storage cleared)
                                              │
                        ┌─────────────────────┴─────────────────────┐
                        ▼                                           ▼
             exchange code → tokens                        throw OAuthCsrfViolation
```

### 2.2. Reason codes

| `reason` | Happens when | UX message |
|---|---|---|
| `state_missing` | callback URL has no `state` query param | "Retorno do Strava sem verificação de segurança. Por favor, tente conectar novamente." |
| `state_mismatch` | `state` present but does not match stored token (wrong value, expired, never-minted, already-consumed, storage tampered) | "Tentativa de conexão inválida detectada. Por favor, tente conectar novamente." |

Both trigger a `colorScheme.error`-tinted snackbar so support can
distinguish it in screen recordings from the yellow `DesignTokens.warning`
used for benign success messages.

---

## 3. Detection signals

### 3.1. Logflare (server-side, post-connect)

When a legitimate user successfully reconnects after a CSRF attempt, the
client uploads no fresh Strava session during that first flow — any spike
in `auth_login_attempts` (L10-09) that correlates with a burst of `strava-webhook` misses is a **possible CSRF-then-connect** pattern worth investigating.

### 3.2. Client logs (per-session)

On any CSRF reject, the app emits:

```
[WARN][StravaAuth] OAuth callback rejected: state_missing (no token exchange performed)
[WARN][StravaOAuthState] OAuth callback rejected: state mismatch
```

Crashlytics / Sentry non-fatal category `OAuthCsrfViolation` should be
wired (if/when Sentry lands on mobile) to count attempts.

### 3.3. CI

```
npm run audit:strava-oauth-state
```

All 17 assertions must pass. Any PR that:

- removes `StravaOAuthStateGuard` primitives,
- weakens `tokenBytes` below 32 or TTL above 30 min,
- loses the `_stateGuard.beginFlow()` / `validateAndConsume(...)` wiring,
- swallows `OAuthCsrfViolation` into a generic `AuthFailed`,
- re-introduces a deep-link handler that parses `omnirunner://strava/callback`,
- removes the dedicated UX branch in `settings_screen.dart`,

will fail this check before merge.

---

## 4. Operational playbooks

### 4.1. Spike of `OAuthCsrfViolation` in Crashlytics

**Meaning**: users are hitting the guard's reject path in the wild.

1. Pull sample sessions and check for a common pattern:
   - Same device model / OS version → possibly a buggy
     `flutter_web_auth_2` interaction (check `app_links` package upgrade
     or a new OEM browser intercepting custom schemes).
   - Same `reason=state_mismatch` but varying devices → possibly a
     phishing attack in the wild. Do NOT relax the check; investigate.
2. Confirm `flutter_secure_storage` is healthy on the affected devices
   (Android StrongBox / iOS Keychain errors would cause the stored
   token to be unreadable on callback, triggering `state_mismatch`).
3. Check for background app-kills mid-flow — iOS Low Power Mode
   will kill the OAuth browser after ~10 minutes, which is exactly
   the TTL. If genuine user complaints cite "I was slow to log in",
   consider bumping the TTL to 15 min (edit
   `StravaOAuthStateGuard.ttl` and update this runbook). The CI check
   allows up to 30 min.
4. **Never** drop the CSRF guard as a "fix" for UX complaints. The
   correct response is to diagnose why the storage contract failed
   for that user class.

### 4.2. A legitimate user is stuck — "Tentativa de conexão inválida"

Quick runbook for L1 support:

1. Ask the user to fully quit the app (swipe it away) and retry.
2. If still failing, ask them to clear the Strava connection from
   `strava.com/settings/apps` and retry (the client-side consent
   flow might be pinned to an old athlete).
3. If still failing, check their device clock. A drift of ≥ 10 min
   will always fail the TTL (we store absolute timestamps, not
   deltas). Ask them to enable "Automatic date & time".
4. If none of the above, escalate with Crashlytics trace: we need to
   know whether the callback URL had a `state` query param at all
   (`reason=state_missing` vs `state_mismatch`).

### 4.3. Deliberate rollout of a tighter TTL

If telemetry shows 99% of connect flows complete in < 3 min, the TTL
can be tightened to 5 min for stronger replay resistance:

1. Edit `StravaOAuthStateGuard.ttl` → `Duration(minutes: 5)`.
2. Run `flutter test test/features/strava/strava_oauth_state_test.dart`
   — the TTL-expiry test uses injectable clock and will still pass.
3. Run `npm run audit:strava-oauth-state` — the CI check allows any
   value ≤ 30 min.
4. Ship it. No database migration, no server redeploy.

### 4.4. Adding a second OAuth provider (Polar, Garmin, etc.)

Do NOT re-implement the state guard per provider. Factor
`StravaOAuthStateGuard` into a generic `OAuthStateGuard` under
`core/oauth/` with a `providerKey` parameter when the second provider
lands. Update this runbook to reflect the new abstraction.

### 4.5. A previously whitelisted `omnirunner://` callback re-appears

The deep-link handler intentionally classifies
`omnirunner://strava/callback?code=…` and
`omnirunner://localhost/exchange_token?code=…` as
`UnknownLinkAction`. Production OAuth runs through `flutter_web_auth_2`
with `omnirunnerauth://` — **that scheme is the ONLY legitimate
callback carrier**. Any PR that re-introduces
`return StravaCallbackAction(...)` in `deep_link_handler.dart`:

- defeats the OS-level web auth session isolation,
- re-opens the pre-L01-29 attack path where any Android app declaring
  `omnirunner://` could intercept an attacker-supplied code,
- fails `npm run audit:strava-oauth-state` (check #13).

If a future consumer truly needs a deep-link-driven OAuth entry point
(e.g. a provider that does not support custom URL schemes), update
this runbook and the CI check in the same PR; the `state` guard still
applies.

---

## 5. Rollback

This is a **defence** layer, not a feature. We do not roll it back.

If the check is causing a genuine incident (e.g. a buggy Dart runtime
upgrade makes `Random.secure()` throw on a subset of devices), the
correct mitigation is to **widen the TTL** or **narrow the failing
device class**, not to drop state validation entirely.

The only acceptable complete rollback is through a formal security
review sign-off.

---

## 6. Invariants

- ✅ `tokenBytes >= 32` (256 bits) — non-negotiable; enforced by CI check.
- ✅ `ttl <= 30 min` — enforced by CI check.
- ✅ `Random.secure()` — enforced by CI check.
- ✅ constant-time compare — enforced by CI check.
- ✅ `OAuthCsrfViolation` distinct from `AuthFailed` in `integrations_failures.dart` — enforced by CI check.
- ✅ `reason ∈ {state_missing, state_mismatch}` — enforced by CI check + tests.
- ✅ Deep-link handler classifies legacy callback paths as `UnknownLinkAction` — enforced by CI check.
- ✅ Settings screen surfaces the violation distinctly from network errors — enforced by CI check.

---

## 7. Cross-references

- [L01-29](../audit/findings/L01-29-ios-universal-link-sem-verificacao-do-apple-app-site-associa.md) — deep-link scheme hardening (Android intent filter, iOS universal link).
- [L10-07](./JWT_ZERO_TRUST_RUNBOOK.md) — zero-trust JWT on Edge Functions: prevents an attacker who DID get a Strava code from invoking backend APIs cross-tenant.
- [L10-09](./ANTI_CREDENTIAL_STUFFING_RUNBOOK.md) — email-scoped login throttle: complementary, not a substitute.
- [`strava_connections` table](../../supabase/migrations/20260221000001_auto_topup_cron.sql) — what the Strava token persistence writes into; any compromise at this layer would cross over into the webhook-driven ingest path.
