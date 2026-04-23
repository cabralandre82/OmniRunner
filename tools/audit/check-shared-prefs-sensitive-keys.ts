/**
 * check-shared-prefs-sensitive-keys.ts
 *
 * L11-05 — CI guard that rejects any Dart call-site that tries to read, write,
 * or delete a SharedPreferences key matching a secret-sounding pattern.
 *
 * Two complementary defences:
 *
 *   1. `omni_runner/lib/core/storage/prefs_safe_key.dart` — runtime Dart
 *      assertion that throws at class-load time if any constant in
 *      `PreferencesKeys` matches the sensitive-word heuristic.
 *
 *   2. This file — PR-time grep that flags every `SharedPreferences.get*(...)`
 *      / `.set*(...)` / `.remove(...)` call-site whose literal key string
 *      matches the same heuristic, AND rejects call-sites that pass a
 *      variable (non-literal) whose NAME matches the heuristic (defense in
 *      depth: if someone renames a catalogue entry and the catalogue-level
 *      assertSafe isn't invoked in tests, the string literal still leaks).
 *
 * Heuristic (case-insensitive word-sense):
 *
 *   token | secret | password | credential | api[_-]?key | auth[_-]?token
 *   | auth[_-]?secret | auth[_-]?code | private[_-]?key | refresh[_-]?token
 *   | access[_-]?token | jwt | bearer | session[_-]?id | session[_-]?token
 *   | session[_-]?secret | oauth[_-]?state | oauth[_-]?token
 *   | oauth[_-]?secret | mfa[_-]?code | mfa[_-]?secret | otp[_-]?code
 *   | otp[_-]?secret | pin[_-]?code | pin[_-]?hash | cvv | card[_-]?number
 *   | ssn | cpf | passport | totp[_-]?secret
 *
 * Word-boundary notes:
 *   Dart `\b` treats `_` as a word character, so `\btoken\b` does NOT match
 *   `access_token`. We use `(?<![a-zA-Z])` / `(?![a-zA-Z])` to allow
 *   hyphen- and underscore-separated keys while still excluding bare letter
 *   neighbours (`tokenize` → does NOT match `token`).
 *
 * Opt-out:
 *   Append `// L11-05-OK: <reason>` on the offending line or the preceding
 *   line. Use this ONLY for false positives that cannot be renamed (e.g., a
 *   third-party SDK key we can't rename). Every opt-out is surfaced in the
 *   report so reviewers can audit them.
 *
 * Scope:
 *   - Scans `omni_runner/lib/**\/*.dart` and `omni_runner/test/**\/*.dart`.
 *   - Matches the following patterns (literal key or variable/getter):
 *       prefs.getString(KEY) | prefs.setString(KEY, ...) | prefs.remove(KEY)
 *       prefs.getBool / getInt / getDouble / getStringList (and set variants)
 *       SharedPreferences.getInstance().then((p) => p.getX(KEY)) — matched via
 *       the same getX / setX / remove regex; the receiver identifier is
 *       whitelisted to `prefs`, `sharedPrefs`, `_prefs`, `p`, `sp`.
 *
 * Usage:
 *   npx tsx tools/audit/check-shared-prefs-sensitive-keys.ts
 *
 * Exit 0 = clean. Exit 1 = at least one violation.
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const LIB_DIR = join(ROOT, "omni_runner", "lib");
const TEST_DIR = join(ROOT, "omni_runner", "test");
const PREFS_KEYS_FILE = join(LIB_DIR, "core", "storage", "preferences_keys.dart");
const SAFE_KEY_FILE = join(LIB_DIR, "core", "storage", "prefs_safe_key.dart");

// Must be kept in lockstep with `_sensitivePatterns` in
// `omni_runner/lib/core/storage/prefs_safe_key.dart`. If the Dart list grows,
// mirror the additions here AND vice versa — ci guard tests the same surface.
const SENSITIVE_PATTERNS: Array<{ label: string; re: RegExp }> = [
  { label: "token", re: /(?<![a-zA-Z])tokens?(?![a-zA-Z])/i },
  { label: "secret", re: /(?<![a-zA-Z])secret(?![a-zA-Z])/i },
  { label: "password", re: /(?<![a-zA-Z])password(?![a-zA-Z])/i },
  { label: "credential", re: /(?<![a-zA-Z])credential(?![a-zA-Z])/i },
  { label: "api_key", re: /(?<![a-zA-Z])api[_-]?key(?![a-zA-Z])/i },
  { label: "auth_token", re: /(?<![a-zA-Z])auth[_-]?(?:token|secret|code)(?![a-zA-Z])/i },
  { label: "private_key", re: /(?<![a-zA-Z])private[_-]?key(?![a-zA-Z])/i },
  { label: "refresh_token", re: /(?<![a-zA-Z])refresh[_-]?token(?![a-zA-Z])/i },
  { label: "access_token", re: /(?<![a-zA-Z])access[_-]?token(?![a-zA-Z])/i },
  { label: "jwt", re: /(?<![a-zA-Z])jwt(?![a-zA-Z])/i },
  { label: "bearer", re: /(?<![a-zA-Z])bearer(?![a-zA-Z])/i },
  { label: "session_id/token/secret", re: /(?<![a-zA-Z])session[_-]?(?:id|token|secret)(?![a-zA-Z])/i },
  { label: "oauth_state/token/secret", re: /(?<![a-zA-Z])oauth[_-]?(?:state|token|secret)(?![a-zA-Z])/i },
  { label: "mfa_code/secret", re: /(?<![a-zA-Z])mfa[_-]?(?:code|secret)(?![a-zA-Z])/i },
  { label: "otp", re: /(?<![a-zA-Z])otp[_-]?(?:code|secret)?(?![a-zA-Z])/i },
  { label: "pin_code/hash", re: /(?<![a-zA-Z])pin[_-]?(?:code|hash)(?![a-zA-Z])/i },
  { label: "cvv", re: /(?<![a-zA-Z])cvv(?![a-zA-Z])/i },
  { label: "card_number", re: /(?<![a-zA-Z])card[_-]?number(?![a-zA-Z])/i },
  { label: "ssn", re: /(?<![a-zA-Z])ssn(?![a-zA-Z])/i },
  { label: "cpf", re: /(?<![a-zA-Z])cpf(?![a-zA-Z])/i },
  { label: "passport", re: /(?<![a-zA-Z])passport(?![a-zA-Z])/i },
  { label: "totp_secret", re: /(?<![a-zA-Z])totp[_-]?secret(?![a-zA-Z])/i },
];

const EXPLICIT_ALLOWLIST = new Set<string>([
  "strava_athlete_name",
  "strava_athlete_id",
]);

const RECEIVER_PATTERN = String.raw`(?:prefs|sharedPrefs|_prefs|p|sp|_pref|sharedPreferences)`;

// Matches any call-site on an assumed SharedPreferences receiver that
// reads/writes/deletes a keyed entry. Captures the key argument.
//
// Examples matched:
//   prefs.getString('my_token')
//   _prefs.setString(PreferencesKeys.someKey, ...)
//   sp.remove(someVariable)
const CALL_SITE_RE = new RegExp(
  String.raw`\b${RECEIVER_PATTERN}\.(?:getString|getBool|getInt|getDouble|getStringList|setString|setBool|setInt|setDouble|setStringList|remove|containsKey)\s*\(\s*([^,)]+?)\s*[,)]`,
  "g"
);

function walkDart(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      // Skip generated + vendor dirs.
      if (entry === ".dart_tool" || entry === "build" || entry === ".build") continue;
      walkDart(full, out);
    } else if (entry.endsWith(".dart")) {
      out.push(full);
    }
  }
  return out;
}

interface Violation {
  file: string;
  line: number;
  column: number;
  snippet: string;
  key: string;
  matchedPattern: string;
}

interface OptOut {
  file: string;
  line: number;
  reason: string;
  snippet: string;
}

function firstMatch(key: string): { label: string } | null {
  for (const { label, re } of SENSITIVE_PATTERNS) {
    if (re.test(key)) return { label };
  }
  return null;
}

function hasOptOut(allLines: string[], lineIdx: number): string | null {
  const thisLine = allLines[lineIdx] ?? "";
  const prevLine = allLines[lineIdx - 1] ?? "";
  const marker = /L11-05-OK\s*:\s*([^*/\n]+)/i;
  const mThis = thisLine.match(marker);
  if (mThis) return mThis[1].trim();
  const mPrev = prevLine.match(marker);
  if (mPrev) return mPrev[1].trim();
  return null;
}

function scanFile(file: string): { violations: Violation[]; optOuts: OptOut[] } {
  const body = readFileSync(file, "utf8");
  const lines = body.split("\n");
  const violations: Violation[] = [];
  const optOuts: OptOut[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // Skip comment-only lines.
    const trimmed = line.trimStart();
    if (trimmed.startsWith("//") || trimmed.startsWith("*")) continue;

    CALL_SITE_RE.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = CALL_SITE_RE.exec(line)) != null) {
      const rawArg = m[1].trim();

      // Extract the "key" we care about:
      //   'literal' | "literal" → strip quotes
      //   PreferencesKeys.xxx   → take xxx
      //   anyIdentifier         → take identifier verbatim
      let key: string;
      const strLit = rawArg.match(/^['"]([^'"]+)['"]$/);
      if (strLit) {
        key = strLit[1];
      } else {
        const prefsKeysAccess = rawArg.match(/^PreferencesKeys\.(\w+)/);
        if (prefsKeysAccess) {
          // Convert camelCase identifier → snake_case for heuristic match,
          // because `omniLocalUserId` maps to the key `omni_local_user_id`.
          key = prefsKeysAccess[1].replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
        } else {
          // Bare identifier / expression. We still test it against the
          // heuristic: a variable called `accessToken` is just as
          // suspicious even if its RUNTIME value is unknown.
          key = rawArg
            .replace(/^[\.\w]*?\.(\w+)$/, "$1")
            .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
            .toLowerCase();
        }
      }

      if (EXPLICIT_ALLOWLIST.has(key)) continue;

      const hit = firstMatch(key);
      if (!hit) continue;

      const optOutReason = hasOptOut(lines, i);
      if (optOutReason) {
        optOuts.push({
          file: relative(ROOT, file),
          line: i + 1,
          reason: optOutReason,
          snippet: line.trim(),
        });
        continue;
      }

      violations.push({
        file: relative(ROOT, file),
        line: i + 1,
        column: (m.index ?? 0) + 1,
        snippet: line.trim(),
        key,
        matchedPattern: hit.label,
      });
    }
  }

  return { violations, optOuts };
}

function ensureDartFilesExist(): void {
  const must: Array<{ path: string; tag: string }> = [
    { path: SAFE_KEY_FILE, tag: "prefs_safe_key.dart" },
    { path: PREFS_KEYS_FILE, tag: "preferences_keys.dart" },
  ];
  for (const f of must) {
    try {
      statSync(f.path);
    } catch {
      console.error(`[FAIL] missing ${f.tag} at ${relative(ROOT, f.path)} — the L11-05 runtime guard must exist before this CI guard is useful`);
      process.exit(1);
    }
  }
}

function ensureCatalogueBindingIntact(): { ok: boolean; reason?: string } {
  const body = readFileSync(PREFS_KEYS_FILE, "utf8");
  const required = [
    "prefs_safe_key.dart",
    "PrefsSafeKey.plain",
    "PrefsSafeKey.prefix",
    "static final List<PrefsSafeKey> allKeys",
  ];
  for (const needle of required) {
    if (!body.includes(needle)) {
      return {
        ok: false,
        reason: `preferences_keys.dart missing "${needle}" — catalogue no longer goes through PrefsSafeKey validation`,
      };
    }
  }
  return { ok: true };
}

function main(): void {
  console.log("L11-05 shared-preferences sensitive-keys guard");

  ensureDartFilesExist();

  const binding = ensureCatalogueBindingIntact();
  if (!binding.ok) {
    console.log(`  [FAIL] catalogue: ${binding.reason}`);
    console.log("\nFAIL — 1 regression(s).");
    process.exit(1);
  }
  console.log("  [OK] catalogue: PreferencesKeys routes every entry through PrefsSafeKey (validated at load time)");

  const files = [...walkDart(LIB_DIR), ...walkDart(TEST_DIR)];
  const allViolations: Violation[] = [];
  const allOptOuts: OptOut[] = [];

  for (const f of files) {
    // The guard file itself exercises the heuristic in docstrings + test
    // fixtures — skip them so we don't self-flag.
    const rel = relative(ROOT, f);
    if (rel === "omni_runner/lib/core/storage/prefs_safe_key.dart") continue;
    if (rel === "omni_runner/test/core/storage/preferences_keys_test.dart") continue;

    const { violations, optOuts } = scanFile(f);
    allViolations.push(...violations);
    allOptOuts.push(...optOuts);
  }

  if (allOptOuts.length > 0) {
    console.log(`  [OK] scan: ${files.length} dart files scanned, ${allOptOuts.length} justified opt-out(s):`);
    for (const o of allOptOuts) {
      console.log(`         • ${o.file}:${o.line} — ${o.reason}`);
    }
  } else {
    console.log(`  [OK] scan: ${files.length} dart files scanned, zero opt-outs (clean)`);
  }

  if (allViolations.length === 0) {
    console.log("  [OK] keys: no SharedPreferences call-site references a sensitive key");
    console.log("\nOK — L11-05 shared-prefs-sensitive-keys invariants hold.");
    process.exit(0);
  }

  console.log(`  [FAIL] keys: ${allViolations.length} violation(s):`);
  for (const v of allViolations) {
    console.log(
      `         • ${v.file}:${v.line}:${v.column} — key "${v.key}" matches pattern "${v.matchedPattern}"\n           snippet: ${v.snippet}`
    );
  }
  console.log(
    "\n  → Fix: use FlutterSecureStorage for this key (see strava_secure_store.dart for the pattern)."
  );
  console.log(
    "  → Or add `// L11-05-OK: <reason>` on the line if this is a false positive that cannot be renamed."
  );
  console.log(`\nFAIL — ${allViolations.length} regression(s).`);
  process.exit(1);
}

main();
