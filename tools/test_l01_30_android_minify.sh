#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# L01-30 — Structural verifier for Android release minify/obfuscate.
#
# Purpose
#   Catch silent regressions of the R8 / ProGuard configuration before they
#   reach CI. The risk being defended is that someone "simplifies"
#   omni_runner/android/app/build.gradle by removing `minifyEnabled true`
#   (or the `proguardFiles` line) — which would re-ship the release APK
#   with anti-cheat thresholds and integrity-detector class names in the
#   clear, exactly the L01-30 attack surface.
#
#   We deliberately keep the lint structural (grep-based) instead of
#   booting the Android Gradle Plugin: the goal is sub-second feedback
#   in hooks and CI matrices that don't have the SDK provisioned.
#
# Defended invariants:
#   1. `minifyEnabled true`        — code shrinking + renaming on
#   2. `shrinkResources true`      — drops orphaned drawables/strings
#   3. `proguardFiles ... 'proguard-rules.pro'` wiring is present
#   4. `proguard-rules.pro` exists and references the integrity
#      detectors as the obfuscation target (the §9 anti-keep block).
#   5. `proguard-rules.pro` does NOT contain any -keep targeting the
#      anti-cheat package — adding one would re-open L01-30.
#
# Exit codes
#   0  all invariants hold
#   1  one or more invariants broken (script prints which)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="${REPO_ROOT}/omni_runner/android/app/build.gradle"
RULES_FILE="${REPO_ROOT}/omni_runner/android/app/proguard-rules.pro"

failures=0
fail() {
  echo "[L01-30] FAIL — $1" >&2
  failures=$((failures + 1))
}
pass() {
  echo "[L01-30] OK   — $1"
}

if [ ! -f "${GRADLE_FILE}" ]; then
  fail "gradle file not found at ${GRADLE_FILE}"
  exit 1
fi
if [ ! -f "${RULES_FILE}" ]; then
  fail "proguard-rules.pro not found at ${RULES_FILE}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 1 — minifyEnabled true on release
# ─────────────────────────────────────────────────────────────────────────────
if grep -E '^\s*minifyEnabled\s+true\b' "${GRADLE_FILE}" >/dev/null; then
  pass "minifyEnabled true present"
else
  fail "missing 'minifyEnabled true' in build.gradle release block"
fi

# Block the regression where someone flips it to false to "fix" a build.
if grep -E '^\s*minifyEnabled\s+false\b' "${GRADLE_FILE}" >/dev/null; then
  fail "explicit 'minifyEnabled false' present — re-opens L01-30"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 2 — shrinkResources true on release
# ─────────────────────────────────────────────────────────────────────────────
if grep -E '^\s*shrinkResources\s+true\b' "${GRADLE_FILE}" >/dev/null; then
  pass "shrinkResources true present"
else
  fail "missing 'shrinkResources true' — saves APK size + drops orphaned assets"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 3 — proguardFiles wiring with our custom rules file
# ─────────────────────────────────────────────────────────────────────────────
if grep -E "proguardFiles[^,]*proguard-android-optimize\.txt[^,]*,\s*'proguard-rules\.pro'" "${GRADLE_FILE}" >/dev/null; then
  pass "proguardFiles wires the AGP optimised defaults + proguard-rules.pro"
else
  fail "missing 'proguardFiles getDefaultProguardFile(...), 'proguard-rules.pro'' wiring"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 4 — proguard-rules.pro acknowledges the integrity-detector
# package as the deliberate obfuscation target (§9 in the file). If the
# §9 banner disappears the next contributor will not know why there are
# no keeps for our anti-cheat code, and may add one.
# ─────────────────────────────────────────────────────────────────────────────
if grep -q 'integrity_detect' "${RULES_FILE}" \
   && grep -q 'L01-30' "${RULES_FILE}"; then
  pass "proguard-rules.pro flags integrity_detect as deliberate obfuscation target"
else
  fail "proguard-rules.pro missing the L01-30 §9 anti-cheat obfuscation banner"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 5 — no -keep targeting the anti-cheat package
# (matches both `-keep class lib.domain.usecases.integrity_detect_*`
#  and any future Java/Kotlin shim under that path).
# ─────────────────────────────────────────────────────────────────────────────
if grep -E '^\s*-keep[a-z]*\s+class\s+[^#\n]*integrity_detect' "${RULES_FILE}" >/dev/null; then
  fail "proguard-rules.pro keeps an integrity_detect symbol — re-opens L01-30"
else
  pass "no -keep rule preserves the integrity_detect symbols (good)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Invariant 6 — recovery escape-hatch is present BUT commented out.
# A live `-dontobfuscate` would silently skip renaming everywhere.
# ─────────────────────────────────────────────────────────────────────────────
if grep -E '^\s*-dontobfuscate\b' "${RULES_FILE}" >/dev/null; then
  fail "active '-dontobfuscate' directive present — disables R8 renaming everywhere"
elif grep -E '^\s*#\s*-dontobfuscate\b' "${RULES_FILE}" >/dev/null; then
  pass "commented '-dontobfuscate' escape-hatch documented but not active"
else
  fail "missing commented '-dontobfuscate' recovery escape-hatch"
fi

if [ "${failures}" -gt 0 ]; then
  echo
  echo "[L01-30] ${failures} invariant(s) violated — see docs/runbooks/ANDROID_RELEASE_SIGNING_RUNBOOK.md" >&2
  exit 1
fi

echo
echo "[L01-30] all invariants hold"
