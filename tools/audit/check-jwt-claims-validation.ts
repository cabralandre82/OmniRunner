/**
 * check-jwt-claims-validation.ts
 *
 * L10-07 — CI guard that enforces zero-trust JWT validation in the
 * shared Edge Function auth helper.
 *
 * Checks:
 *   1. supabase/functions/_shared/auth.ts contains the expected
 *      primitives (decodeJwtPayload, assertClaimsShape, RequireUserOptions
 *      with allowedAudiences/allowedClients, env overrides, machine
 *      reasons invalid_issuer/audience_mismatch/client_mismatch).
 *   2. No Edge Function re-implements a bearer-auth path that would
 *      bypass requireUser (grep for raw `auth.getUser` outside the
 *      shared helper).
 *   3. requireUser call sites are not disabling claims checks
 *      (`skipClaimsCheck: true` only allowed in tests/docs).
 *
 * Usage:
 *   npm run audit:jwt-claims-validation
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

const SHARED_AUTH = "supabase/functions/_shared/auth.ts";
const FUNCTIONS_DIR = "supabase/functions";

const REQUIRED_MARKERS = [
  "export function decodeJwtPayload",
  "export function assertClaimsShape",
  "AUTH_JWT_EXPECTED_ISSUERS",
  "AUTH_JWT_ALLOWED_AUDIENCES",
  "allowedAudiences",
  "allowedClients",
  "invalid_issuer",
  "audience_mismatch",
  "missing_audience",
  "client_mismatch",
  "x-omni-client",
];

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry.startsWith(".")) continue;
    const full = path.join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, acc);
    else if (entry === "index.ts") acc.push(full);
  }
  return acc;
}

function main(): number {
  console.log("L10-07: checking zero-trust JWT validation…");
  const failures: string[] = [];

  let shared: string;
  try {
    shared = readFileSync(SHARED_AUTH, "utf8");
  } catch (e) {
    console.error(`\nERROR: cannot read ${SHARED_AUTH}: ${(e as Error).message}`);
    return 1;
  }

  for (const marker of REQUIRED_MARKERS) {
    if (!shared.includes(marker)) {
      failures.push(`missing marker in ${SHARED_AUTH}: "${marker}"`);
    }
  }

  const entries = walk(FUNCTIONS_DIR);

  for (const file of entries) {
    if (file.includes("/_shared/")) continue;
    const src = readFileSync(file, "utf8");

    if (/skipClaimsCheck\s*:\s*true/.test(src)) {
      failures.push(`${file}: skipClaimsCheck: true is not allowed in production Edge Functions`);
    }

    if (
      /auth\.getUser\s*\(/.test(src) &&
      !/requireUser/.test(src)
    ) {
      failures.push(
        `${file}: calls auth.getUser directly without using the shared requireUser helper`,
      );
    }
  }

  if (failures.length > 0) {
    console.error(`\n  FAIL`);
    for (const f of failures) console.error(`   - ${f}`);
    console.error(
      `\nSee docs/runbooks/JWT_ZERO_TRUST_RUNBOOK.md and docs/audit/findings/L10-07-*.md.`,
    );
    return 1;
  }

  console.log(`  shared helper: OK`);
  console.log(`  edge functions: OK (${entries.length} scanned)`);
  console.log("\nOK — zero-trust JWT validation is in place.");
  return 0;
}

process.exit(main());
