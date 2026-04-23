/**
 * check-strava-oauth-state.ts
 *
 * L07-04 — CI guard that enforces the OAuth 2.0 §10.12 `state`
 * parameter defence around the Flutter Strava OAuth flow.
 *
 * Strava is the single source of truth for activities (runs, pace,
 * GPS) — a successful login-CSRF would graft an attacker-controlled
 * Strava account onto the victim's Omni Runner profile and poison
 * anti-cheat baselines, challenge progress, and ranking.
 *
 * The runtime defence lives in
 *   `omni_runner/lib/features/strava/data/strava_oauth_state.dart`
 * and is wired into
 *   `omni_runner/lib/features/strava/data/strava_auth_repository_impl.dart`
 * (see `_stateGuard.beginFlow()` / `validateAndConsume()`).
 *
 * This CI check ensures the wiring does not regress: any PR that
 * removes the guard, the CSRF error class, or the dedicated UX path
 * must fail this check before merge.
 *
 * Checks:
 *   1. `strava_oauth_state.dart` exposes `StravaOAuthStateGuard` with
 *      `beginFlow`, `validateAndConsume`, `clear` and a `tokenBytes`
 *      of at least 32 (256 bits).
 *   2. `strava_auth_repository_impl.dart` actually calls both the
 *      `beginFlow()` and `validateAndConsume()` hooks AND throws
 *      `OAuthCsrfViolation` (not generic `AuthFailed`) when the
 *      callback fails the state check.
 *   3. The `OAuthCsrfViolation` class is declared in
 *      `integrations_failures.dart` and re-exported from
 *      `strava_failures.dart` so the UI layer can pattern-match on it.
 *   4. `deep_link_handler.dart` rejects the legacy
 *      `omnirunner://strava/callback` and `omnirunner://localhost/exchange_token`
 *      paths as `UnknownLinkAction` — see L01-29.
 *   5. The Strava auth repository test has coverage for the CSRF
 *      path (state_mismatch AND state_missing reasons).
 *
 * Usage:
 *   npm run audit:strava-oauth-state
 */

import { readFileSync } from "node:fs";

type Check = { file: string; label: string; ok: boolean; detail?: string };

function has(src: string, needle: string | RegExp): boolean {
  return needle instanceof RegExp ? needle.test(src) : src.includes(needle);
}

function run(): number {
  console.log("L07-04: checking Strava OAuth state CSRF defence…");
  const checks: Check[] = [];

  const guardFile =
    "omni_runner/lib/features/strava/data/strava_oauth_state.dart";
  const repoFile =
    "omni_runner/lib/features/strava/data/strava_auth_repository_impl.dart";
  const failuresFile = "omni_runner/lib/core/errors/integrations_failures.dart";
  const barrelFile = "omni_runner/lib/core/errors/strava_failures.dart";
  const deeplinkFile =
    "omni_runner/lib/core/deep_links/deep_link_handler.dart";
  const repoTestFile =
    "omni_runner/test/features/strava/strava_auth_repository_test.dart";
  const settingsFile =
    "omni_runner/lib/presentation/screens/settings_screen.dart";

  let guard: string;
  let repo: string;
  let failures: string;
  let barrel: string;
  let deeplink: string;
  let repoTest: string;
  let settings: string;

  try {
    guard = readFileSync(guardFile, "utf8");
    repo = readFileSync(repoFile, "utf8");
    failures = readFileSync(failuresFile, "utf8");
    barrel = readFileSync(barrelFile, "utf8");
    deeplink = readFileSync(deeplinkFile, "utf8");
    repoTest = readFileSync(repoTestFile, "utf8");
    settings = readFileSync(settingsFile, "utf8");
  } catch (e) {
    console.error(`\nERROR: cannot read expected L07-04 source: ${(e as Error).message}`);
    return 1;
  }

  // 1. Guard primitives
  checks.push({
    file: guardFile,
    label: "StravaOAuthStateGuard.beginFlow declared",
    ok: has(guard, /Future<String>\s+beginFlow\s*\(/),
  });
  checks.push({
    file: guardFile,
    label: "StravaOAuthStateGuard.validateAndConsume declared",
    ok: has(guard, /Future<bool>\s+validateAndConsume\s*\(/),
  });
  checks.push({
    file: guardFile,
    label: "tokenBytes is at least 32 (256 bits of entropy)",
    ok: (() => {
      const m = guard.match(/static\s+const\s+int\s+tokenBytes\s*=\s*(\d+)/);
      return m !== null && Number(m[1]) >= 32;
    })(),
  });
  checks.push({
    file: guardFile,
    label: "uses Random.secure() CSPRNG by default",
    ok: has(guard, "Random.secure()"),
  });
  checks.push({
    file: guardFile,
    label: "TTL is bounded and <= 30 minutes",
    ok: (() => {
      const m = guard.match(/Duration\s+ttl\s*=\s*Duration\(minutes:\s*(\d+)\)/);
      return m !== null && Number(m[1]) <= 30;
    })(),
  });
  checks.push({
    file: guardFile,
    label: "uses constant-time comparison",
    ok: has(guard, "_constantTimeEquals"),
  });

  // 2. Repository wiring
  checks.push({
    file: repoFile,
    label: "authenticate() mints state via _stateGuard.beginFlow()",
    ok: has(repo, "_stateGuard.beginFlow()"),
  });
  checks.push({
    file: repoFile,
    label: "authenticate() validates callback via validateAndConsume()",
    ok: has(repo, "_stateGuard.validateAndConsume(returnedState)"),
  });
  checks.push({
    file: repoFile,
    label: "state failure throws OAuthCsrfViolation (not generic AuthFailed)",
    ok: has(repo, "throw OAuthCsrfViolation(") && !has(repo, "throw const AuthFailed('OAuth state mismatch"),
  });
  checks.push({
    file: repoFile,
    label: "differentiates state_missing vs state_mismatch reason",
    ok: has(repo, "state_missing") && has(repo, "state_mismatch"),
  });
  checks.push({
    file: repoFile,
    label: "passes state to buildAuthorizationUrl",
    ok: has(repo, /buildAuthorizationUrl\([^)]*state\s*:\s*state/),
  });

  // 3. Failure class exported
  checks.push({
    file: failuresFile,
    label: "OAuthCsrfViolation final class declared",
    ok: has(failures, /final\s+class\s+OAuthCsrfViolation\s+extends\s+IntegrationFailure/),
  });
  checks.push({
    file: barrelFile,
    label: "strava_failures.dart re-exports OAuthCsrfViolation",
    ok: has(barrel, "OAuthCsrfViolation"),
  });

  // 4. Deep-link handler denies legacy callback paths (L01-29)
  checks.push({
    file: deeplinkFile,
    label: "legacy omnirunner://strava/callback is NOT parsed as StravaCallbackAction",
    ok: !/return\s+StravaCallbackAction\(/.test(deeplink),
  });

  // 5. Test coverage
  checks.push({
    file: repoTestFile,
    label: "test asserts OAuthCsrfViolation for forged callback",
    ok: has(repoTest, "OAuthCsrfViolation") && has(repoTest, "state_mismatch"),
  });
  checks.push({
    file: repoTestFile,
    label: "test asserts OAuthCsrfViolation for missing state param",
    ok: has(repoTest, "state_missing"),
  });

  // 6. UX pattern-matches OAuthCsrfViolation separately from generic errors
  checks.push({
    file: settingsFile,
    label: "settings_screen surfaces OAuthCsrfViolation distinctly",
    ok: has(settings, "on OAuthCsrfViolation"),
  });

  const failed = checks.filter((c) => !c.ok);
  for (const c of checks) {
    const mark = c.ok ? "OK" : "FAIL";
    console.log(`  [${mark}] ${c.file}: ${c.label}`);
  }

  if (failed.length > 0) {
    console.error(`\n  FAIL — ${failed.length} regression(s)`);
    console.error(
      `\nSee docs/runbooks/STRAVA_OAUTH_CSRF_RUNBOOK.md and docs/audit/findings/L07-04-*.md.`,
    );
    return 1;
  }

  console.log(`\nOK — Strava OAuth CSRF defence (L07-04 + L01-29) is wired.`);
  return 0;
}

process.exit(run());
