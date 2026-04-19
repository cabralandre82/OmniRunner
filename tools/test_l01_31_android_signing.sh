#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# L01-31 — Structural verifier for Android release signing safety net.
#
# Purpose
#   Catch silent regressions of the release-signing fallback before they
#   reach CI. The risk being defended is that someone "simplifies"
#   omni_runner/android/app/build.gradle back to a silent
#   `signingConfigs.debug` fallback when key.properties is missing, and
#   the CI pipeline happily ships a debug-signed AAB to Google Play.
#
#   The audit finding L01-31 traced the exact `?: signingConfigs.debug`
#   ternary that this script forbids. We also check that the explicit
#   throw + override flag are still wired in, so future contributors
#   cannot accidentally remove half of the defence.
#
# Why not a Gradle integration test?
#   Running `./gradlew assembleProdRelease` without a keystore takes
#   minutes, requires the Android SDK, and most importantly cannot
#   succeed in this repo's GitHub Actions matrix without first wiring
#   secrets. A structural lint is sub-second, runs in any environment,
#   and is the right granularity for "did the gradle file regress".
#
# Exit codes
#   0  all invariants hold
#   1  one or more invariants broken (script prints which)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="${REPO_ROOT}/omni_runner/android/app/build.gradle"

if [ ! -f "${GRADLE_FILE}" ]; then
  echo "[L01-31] FAIL — gradle file not found at ${GRADLE_FILE}" >&2
  exit 1
fi

failures=0
fail() {
  echo "[L01-31] FAIL — $1" >&2
  failures=$((failures + 1))
}
pass() {
  echo "[L01-31] OK   — $1"
}

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 1 — no silent debug fallback
#
# The original audit pattern was:
#   signingConfig keystorePropertiesFile.exists() ? signingConfigs.release
#                                                  : signingConfigs.debug
# Any unconditional reference to `signingConfigs.debug` *inside the release
# block* would re-introduce the vulnerability. We use ripgrep when available,
# fall back to grep -E otherwise (CI has both).
# ─────────────────────────────────────────────────────────────────────────────
if grep -E '\?\s*signingConfigs\.release\s*:\s*signingConfigs\.debug' "${GRADLE_FILE}" >/dev/null; then
  fail "ternary fallback to signingConfigs.debug detected — re-introduces L01-31"
else
  pass "no ternary debug fallback present"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 2 — fail-loud throw is present
# ─────────────────────────────────────────────────────────────────────────────
if grep -q 'throw new GradleException' "${GRADLE_FILE}" \
   && grep -q 'L01-31' "${GRADLE_FILE}"; then
  pass "GradleException with L01-31 reference present"
else
  fail "missing fail-loud throw referencing L01-31"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 3 — release-task detection is present
# ─────────────────────────────────────────────────────────────────────────────
if grep -q 'isReleaseTaskRequested' "${GRADLE_FILE}" \
   && grep -q 'gradle\.startParameter\.taskNames' "${GRADLE_FILE}"; then
  pass "release-task detection wired via startParameter.taskNames"
else
  fail "missing isReleaseTaskRequested / startParameter.taskNames detection"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 4 — opt-in override flag is present (and ONLY consulted in the
# non-CI path; CI must never set it).
# ─────────────────────────────────────────────────────────────────────────────
if grep -q 'allowReleaseDebugSigning' "${GRADLE_FILE}"; then
  pass "allowReleaseDebugSigning override flag is wired"
else
  fail "missing allowReleaseDebugSigning override flag"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 5 — release.yml MUST NOT pass -PallowReleaseDebugSigning to
# fastlane / gradle. CI shipping a debug-signed APK defeats the purpose.
# ─────────────────────────────────────────────────────────────────────────────
RELEASE_WF="${REPO_ROOT}/.github/workflows/release.yml"
if [ -f "${RELEASE_WF}" ]; then
  if grep -q 'allowReleaseDebugSigning' "${RELEASE_WF}"; then
    fail "release.yml references allowReleaseDebugSigning — CI must never enable it"
  else
    pass "release.yml does not enable allowReleaseDebugSigning"
  fi
else
  echo "[L01-31] WARN — release.yml not found; skipping CI-side check"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 6 — release.yml restores key.properties + keystore from secrets
# (the matching half of the gradle defence; without this the CI build would
# always fail post-fix, which would be loud but useless).
# ─────────────────────────────────────────────────────────────────────────────
if [ -f "${RELEASE_WF}" ]; then
  if grep -q 'ANDROID_KEYSTORE_BASE64' "${RELEASE_WF}" \
     && grep -q 'ANDROID_KEY_PROPERTIES' "${RELEASE_WF}"; then
    pass "release.yml restores keystore + key.properties from CI secrets"
  else
    fail "release.yml missing ANDROID_KEYSTORE_BASE64 / ANDROID_KEY_PROPERTIES wiring"
  fi
fi

if [ "${failures}" -gt 0 ]; then
  echo
  echo "[L01-31] ${failures} invariant(s) violated — see docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md" >&2
  exit 1
fi

echo
echo "[L01-31] all invariants hold"
