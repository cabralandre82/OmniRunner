/**
 * check-utm-attribution.ts
 *
 * L15-01 — CI guard for the UTM attribution capture pipeline.
 *
 * Invariants:
 *   1. Migration creates `marketing_attribution_events` with the
 *      expected CHECK constraints, RLS enabled, indexes on
 *      (user_id, created_at), (campaign, created_at), and
 *      (event_type, created_at).
 *   2. Migration adds `profiles.attribution jsonb` and a
 *      SECURITY DEFINER trigger that snapshots first-touch only.
 *   3. Events table is registered in audit_logs_retention_config.
 *   4. Self-test asserts identity CHECK + source-length CHECK.
 *   5. Portal lib `attribution.ts` reads marketing consent before
 *      writing the cookie, clamps field length, bases64-encodes,
 *      and honors first-touch (no overwrite).
 *   6. Portal route `/api/attribution/capture` exists, validates
 *      body with zod, truncates IP, hashes UA, writes via
 *      service-role, and rate-limits.
 *
 * Usage: npm run audit:utm-attribution
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const migPath = resolve(
  ROOT,
  "supabase/migrations/20260421520000_l15_01_utm_attribution.sql",
);
const mig = safeRead(migPath, "L15-01 migration present");
if (mig) {
  push(
    "creates marketing_attribution_events table",
    /CREATE TABLE IF NOT EXISTS public\.marketing_attribution_events/.test(mig),
  );
  push(
    "event_type CHECK restricts to known set",
    /event_type IN \('visit','signup','activation','conversion'\)/.test(mig),
  );
  push(
    "identity CHECK requires user_id OR anonymous_id",
    /chk_attribution_has_identity[\s\S]{0,80}user_id IS NOT NULL OR anonymous_id IS NOT NULL/.test(
      mig,
    ),
  );
  push(
    "source length CHECK present",
    /chk_attribution_source_length/.test(mig) && /length\(source\) <= 128/.test(mig),
  );
  push(
    "campaign length CHECK present",
    /chk_attribution_campaign_length/.test(mig) && /length\(campaign\) <= 200/.test(mig),
  );
  push(
    "landing length CHECK present",
    /chk_attribution_landing_length/.test(mig) && /length\(landing_path\) <= 1024/.test(mig),
  );
  push(
    "RLS enabled",
    /ALTER TABLE public\.marketing_attribution_events ENABLE ROW LEVEL SECURITY/.test(
      mig,
    ),
  );
  push(
    "policy: own user + platform_admin read",
    /user_id = auth\.uid\(\)/.test(mig) && /platform_role = 'admin'/.test(mig),
  );
  push(
    "idx on (user_id, created_at)",
    /idx_attribution_user[\s\S]{0,160}\(user_id, created_at DESC\)/.test(mig),
  );
  push(
    "partial idx on campaign",
    /idx_attribution_campaign[\s\S]{0,200}WHERE campaign IS NOT NULL/.test(mig),
  );
  push(
    "idx on event_type",
    /idx_attribution_event_type/.test(mig),
  );
  push(
    "adds profiles.attribution jsonb",
    /ADD COLUMN IF NOT EXISTS attribution jsonb/.test(mig),
  );
  push(
    "defines fn_attribution_first_touch",
    /CREATE OR REPLACE FUNCTION public\.fn_attribution_first_touch/.test(mig),
  );
  push(
    "first-touch trigger is AFTER INSERT",
    /CREATE TRIGGER trg_attribution_first_touch[\s\S]{0,160}AFTER INSERT ON public\.marketing_attribution_events/.test(
      mig,
    ),
  );
  push(
    "first-touch trigger is SECURITY DEFINER",
    /fn_attribution_first_touch[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "first-touch skips when snapshot already set",
    /IF v_snapshot IS NOT NULL THEN\s*RETURN NEW;/.test(mig),
  );
  push(
    "registers 180-day retention",
    /INSERT INTO public\.audit_logs_retention_config[\s\S]{0,400}'marketing_attribution_events'[\s\S]{0,80}180/.test(
      mig,
    ),
  );
  push(
    "self-test: profiles.attribution missing",
    /profiles\.attribution column missing or wrong type/.test(mig),
  );
  push(
    "self-test: trigger missing",
    /first-touch trigger missing/.test(mig),
  );
  push(
    "self-test: identity CHECK blocks",
    /identity CHECK should have blocked identity-less row/.test(mig),
  );
  push(
    "self-test: source length CHECK fires",
    /source length CHECK should have fired/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const libPath = resolve(ROOT, "portal/src/lib/attribution.ts");
const lib = safeRead(libPath, "attribution.ts present");
if (lib) {
  push(
    "lib gates on consentAllowsMarketing()",
    /consentAllowsMarketing\(\)/.test(lib),
  );
  push(
    "lib respects first-touch (no overwrite if cookie exists)",
    /document\.cookie\.includes\(`\$\{COOKIE_NAME\}=`\)/.test(lib),
  );
  push(
    "lib clamps UTM field length",
    /trimmed\.slice\(0, MAX_LEN\)/.test(lib) && /MAX_LEN = 200/.test(lib),
  );
  push(
    "lib reads from all five UTM keys",
    /source[\s\S]{0,30}medium[\s\S]{0,30}campaign[\s\S]{0,30}term[\s\S]{0,30}content/.test(
      lib,
    ),
  );
  push(
    "lib sets SameSite=Lax + Path=/",
    /SameSite=Lax/.test(lib) && /Path=\//.test(lib),
  );
  push(
    "lib exposes readAttributionCookie for server use",
    /export function readAttributionCookie/.test(lib),
  );
}

const routePath = resolve(
  ROOT,
  "portal/src/app/api/attribution/capture/route.ts",
);
const route = safeRead(routePath, "attribution capture route present");
if (route) {
  push(
    "route validates body with zod strict schema",
    /\.strict\(\)/.test(route) &&
      /z\.enum\(\[[\s\S]{0,80}"visit"[\s\S]{0,120}"conversion"[\s\S]{0,10}\]\)/.test(
        route,
      ),
  );
  push(
    "route truncates IP to /24 or /48",
    /\/24/.test(route) && /\/48/.test(route),
  );
  push(
    "route hashes user-agent (sha256)",
    /createHash\(\"sha256\"\)/.test(route),
  );
  push(
    "route writes via service-role client",
    /createServiceClient\(\)/.test(route),
  );
  push(
    "route rate-limits",
    /rateLimit\(/.test(route),
  );
  push(
    "route refuses when no identity (user OR anonymous_id)",
    /NO_IDENTITY/.test(route),
  );
  push(
    "route wrapped in withErrorHandler",
    /withErrorHandler\(\s*_post/.test(route),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L15-01-zero-utm-tracking-no-produto.md",
);
const finding = safeRead(findingPath, "L15-01 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421520000_l15_01_utm_attribution\.sql/.test(finding),
  );
  push(
    "finding references portal lib",
    /portal\/src\/lib\/attribution\.ts/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} utm-attribution checks passed.`,
);
if (failed > 0) {
  console.error("\nL15-01 invariants broken.");
  process.exit(1);
}
