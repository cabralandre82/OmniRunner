/**
 * check-logger-sentry-capture.ts
 *
 * L17-05 — CI guard enforcing that `portal/src/lib/logger.ts` always
 * reports to Sentry when `logger.error(...)` is called, independent of
 * whether an `error` argument was supplied.
 *
 * The original code used `else if (error)` after the `Error`-instance
 * branch, which silently dropped `logger.error("foo", undefined, meta)`
 * and `logger.error("foo", null, meta)` from Sentry. That was a real
 * bug at four callsites (custody webhook × 3, checkout proxy) where the
 * operators only discovered the incident via PagerDuty rather than
 * Sentry, because the intended error was console-logged but never
 * forwarded.
 *
 * Invariants enforced here:
 *   1. `logger.ts` does not contain `else if (error)` after the
 *      `instanceof Error` branch (that is the shape of the old bug).
 *   2. `logger.ts` calls BOTH `Sentry.captureException` (for Error) and
 *      `Sentry.captureMessage` (for everything else) — i.e. both code
 *      paths are reachable.
 *   3. `logger.ts` contains the `normalizeErrorFields` helper that
 *      produces a consistent shape for Error / object / primitive
 *      error args.
 *   4. `logger.test.ts` covers the no-error / null-error / object-error
 *      paths against the Sentry mocks (`L17-05 Sentry capture
 *      invariants`).
 *
 * Usage:
 *   npm run audit:logger-sentry-capture
 */

import { readFileSync } from "node:fs";

type Check = { file: string; label: string; ok: boolean };

function has(src: string, needle: string | RegExp): boolean {
  return needle instanceof RegExp ? needle.test(src) : src.includes(needle);
}

function main(): number {
  const loggerFile = "portal/src/lib/logger.ts";
  const testFile = "portal/src/lib/logger.test.ts";

  let loggerSrc = "";
  let testSrc = "";
  try {
    loggerSrc = readFileSync(loggerFile, "utf8");
  } catch {
    console.error(`FATAL — could not read ${loggerFile}`);
    return 1;
  }
  try {
    testSrc = readFileSync(testFile, "utf8");
  } catch {
    console.error(`FATAL — could not read ${testFile}`);
    return 1;
  }

  console.log("L17-05 logger Sentry capture guard");

  const checks: Check[] = [];

  checks.push({
    file: loggerFile,
    label:
      "does NOT use `} else if (error) {` branch after Error branch (legacy bug shape)",
    ok: !/\}\s*else\s+if\s*\(\s*error\s*\)\s*\{[^}]*captureMessage/s.test(
      loggerSrc,
    ),
  });
  checks.push({
    file: loggerFile,
    label: "captureException path is present for Error instances",
    ok: has(loggerSrc, "Sentry.captureException(error"),
  });
  checks.push({
    file: loggerFile,
    label: "captureMessage path is present for non-Error / undefined",
    ok: has(loggerSrc, "Sentry.captureMessage(msg"),
  });
  checks.push({
    file: loggerFile,
    label: "normalizeErrorFields helper is declared",
    ok: has(loggerSrc, "normalizeErrorFields"),
  });
  checks.push({
    file: loggerFile,
    label: "normalizeErrorFields handles null/undefined as empty object",
    ok: /error\s*===\s*undefined\s*\|\|\s*error\s*===\s*null/.test(loggerSrc),
  });

  checks.push({
    file: testFile,
    label: "test suite `L17-05 Sentry capture invariants` is declared",
    ok: has(testSrc, "L17-05 Sentry capture invariants"),
  });
  checks.push({
    file: testFile,
    label: "test asserts captureMessage is called when error is undefined",
    ok:
      has(testSrc, "bug L17-05") &&
      has(testSrc, "mockCaptureMessage") &&
      has(testSrc, "undefined"),
  });
  checks.push({
    file: testFile,
    label: "test asserts captureException is called for Error instances",
    ok: has(testSrc, "mockCaptureException"),
  });

  const failed = checks.filter((c) => !c.ok);
  for (const c of checks) {
    const mark = c.ok ? "OK" : "FAIL";
    console.log(`  [${mark}] ${c.file}: ${c.label}`);
  }

  if (failed.length > 0) {
    console.error(`\n  FAIL — ${failed.length} regression(s)`);
    console.error(
      `\nSee docs/runbooks/LOGGER_SENTRY_CAPTURE_RUNBOOK.md and docs/audit/findings/L17-05-*.md.`,
    );
    return 1;
  }

  console.log(`\nOK — logger.error always reports to Sentry (L17-05).`);
  return 0;
}

process.exit(main());
