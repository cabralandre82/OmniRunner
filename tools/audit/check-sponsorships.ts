/**
 * check-sponsorships.ts
 *
 * L16-05 — CI guard for sponsorships / brand integrations schema.
 *
 * Corrected by L22-02 (2026-04-21): OmniCoins are earned only inside
 * challenges; sponsorships deliver value through physical swag, equipment
 * discounts, brand exposure, etc. — NEVER through coin stipends.
 *
 * Invariants:
 *   1. `public.brands` exists with slug/display_name/URL CHECKs, unique
 *      slug, RLS enabled, public-read policy on active brands.
 *   2. `public.sponsorships` exists with state-machine CHECK, contract
 *      window CHECK, equipment discount CHECK, active-requires-approval
 *      CHECK, partial UNIQUE(group_id, brand_id) for non-terminal states,
 *      three indexes.  It must NOT carry coin-budget columns after
 *      the L22-02 correction migration.
 *   3. `public.sponsorship_athletes` join table with composite PK,
 *      timestamp ordering CHECK, two partial indexes.
 *   4. `fn_sponsorship_activate(uuid)` is SECURITY DEFINER,
 *      platform_admin-or-service-role only, validates transition and
 *      expiry, stamps approved_by/at.
 *   5. `fn_sponsorship_enroll_athlete(uuid)` authenticated-only with
 *      NOT_ACTIVE / MEMBERSHIP_REQUIRED, idempotent via ON CONFLICT.
 *   6. `fn_sponsorship_opt_out_athlete(uuid)` idempotent.
 *   7. After L22-02 correction, fn_sponsorship_distribute_monthly_coins
 *      MUST NOT exist in the repo migrations as an active function —
 *      the correction migration drops it.
 *   8. After L22-02 correction, the coin-budget columns MUST be dropped
 *      from sponsorships and no coin_ledger INSERT MUST remain in the
 *      sponsorship codepath.
 *   9. Self-test references the remaining CHECK constraints and index.
 *  10. Both migrations run in single transactions.
 *  11. Finding references both migrations + documents the challenge-only
 *      coin policy.
 *
 * Usage: npm run audit:sponsorships
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
  "supabase/migrations/20260421620000_l16_05_sponsorships.sql",
);
const mig = safeRead(migPath, "L16-05 migration file present");

if (mig) {
  // brands table.
  push(
    "creates brands table",
    /CREATE TABLE IF NOT EXISTS public\.brands/.test(mig),
  );
  push(
    "brands slug CHECK shape",
    /CONSTRAINT brands_slug_shape CHECK \(slug ~ '\^\[a-z0-9\]\[a-z0-9-\]\{1,39\}\$'\)/.test(mig),
  );
  push(
    "brands display_name length CHECK 2..60",
    /CONSTRAINT brands_display_name_len CHECK \(length\(display_name\) BETWEEN 2 AND 60\)/.test(mig),
  );
  push(
    "brands website_url CHECK https",
    /CONSTRAINT brands_website_url_https[\s\S]{0,200}\^https:\/\//.test(mig),
  );
  push(
    "brands logo_url CHECK https",
    /CONSTRAINT brands_logo_url_https[\s\S]{0,200}\^https:\/\//.test(mig),
  );
  push(
    "brands slug UNIQUE index",
    /CREATE UNIQUE INDEX IF NOT EXISTS brands_slug_unique ON public\.brands \(slug\)/.test(mig),
  );
  push(
    "brands RLS enabled",
    /ALTER TABLE public\.brands ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "brands public-read policy for active brands",
    /brands_public_read[\s\S]{0,200}active = TRUE/.test(mig),
  );

  // sponsorships table.
  push(
    "creates sponsorships table",
    /CREATE TABLE IF NOT EXISTS public\.sponsorships/.test(mig),
  );
  push(
    "sponsorships FK to coaching_groups ON DELETE CASCADE",
    /group_id[\s\S]{0,200}REFERENCES public\.coaching_groups\(id\) ON DELETE CASCADE/.test(mig),
  );
  push(
    "sponsorships FK to brands ON DELETE RESTRICT",
    /brand_id[\s\S]{0,120}REFERENCES public\.brands\(id\) ON DELETE RESTRICT/.test(mig),
  );
  push(
    "sponsorships status CHECK enum",
    /CHECK \(status IN \('draft','active','paused','ended','cancelled'\)\)/.test(mig),
  );
  push(
    "sponsorships contract window CHECK",
    /CONSTRAINT sponsorships_contract_window CHECK \(contract_end > contract_start\)/.test(mig),
  );
  push(
    "sponsorships equipment_discount 0..90",
    /CONSTRAINT sponsorships_equipment_discount_range[\s\S]{0,120}equipment_discount_pct >= 0 AND equipment_discount_pct <= 90/.test(mig),
  );
  push(
    "sponsorships active requires approval CHECK",
    /CONSTRAINT sponsorships_active_requires_approval CHECK \(\s*status <> 'active' OR \(approved_by IS NOT NULL AND approved_at IS NOT NULL\)\s*\)/.test(mig),
  );
  push(
    "sponsorships partial UNIQUE on group+brand for non-terminal",
    /CREATE UNIQUE INDEX IF NOT EXISTS sponsorships_active_per_group_brand[\s\S]{0,200}WHERE status IN \('draft','active','paused'\)/.test(mig),
  );
  push(
    "sponsorships active-status partial index",
    /CREATE INDEX IF NOT EXISTS sponsorships_active_idx[\s\S]{0,200}WHERE status = 'active'/.test(mig),
  );
  push(
    "sponsorships RLS enabled",
    /ALTER TABLE public\.sponsorships ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "sponsorships staff-read policy on coaching_members + platform_admin",
    /sponsorships_staff_read[\s\S]{0,400}coaching_members[\s\S]{0,400}platform_role = 'admin'/.test(mig),
  );

  // athletes join.
  push(
    "creates sponsorship_athletes join",
    /CREATE TABLE IF NOT EXISTS public\.sponsorship_athletes/.test(mig),
  );
  push(
    "sponsorship_athletes composite PK",
    /PRIMARY KEY \(sponsorship_id, user_id\)/.test(mig),
  );
  push(
    "sponsorship_athletes timestamp ordering CHECK",
    /CONSTRAINT sponsorship_athletes_timestamp_consistency[\s\S]{0,200}opted_out_at IS NULL OR opted_out_at >= enrolled_at/.test(mig),
  );
  push(
    "sponsorship_athletes user partial index",
    /CREATE INDEX IF NOT EXISTS sponsorship_athletes_user_idx[\s\S]{0,200}WHERE opted_out_at IS NULL/.test(mig),
  );
  push(
    "sponsorship_athletes active partial index",
    /CREATE INDEX IF NOT EXISTS sponsorship_athletes_active_idx[\s\S]{0,200}WHERE opted_out_at IS NULL/.test(mig),
  );
  push(
    "sponsorship_athletes RLS enabled",
    /ALTER TABLE public\.sponsorship_athletes ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "sponsorship_athletes self-read policy",
    /sponsorship_athletes_self_read[\s\S]{0,400}user_id = auth\.uid\(\)/.test(mig),
  );

  // RPCs (non-coin ones remain).
  push(
    "defines fn_sponsorship_activate SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_sponsorship_activate[\s\S]{0,600}SECURITY DEFINER/.test(mig),
  );
  push(
    "activate gates on platform_admin when not service_role",
    /fn_sponsorship_activate[\s\S]{0,1600}platform_role = 'admin'[\s\S]{0,200}RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'/.test(mig),
  );
  push(
    "activate raises CONTRACT_EXPIRED",
    /RAISE EXCEPTION 'CONTRACT_EXPIRED' USING ERRCODE = 'P0003'/.test(mig),
  );
  push(
    "activate raises INVALID_TRANSITION",
    /fn_sponsorship_activate[\s\S]{0,2000}RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'P0003'/.test(mig),
  );
  push(
    "activate grants to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_sponsorship_activate\(UUID\) TO authenticated, service_role/.test(mig),
  );

  push(
    "defines fn_sponsorship_enroll_athlete SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_sponsorship_enroll_athlete[\s\S]{0,600}SECURITY DEFINER/.test(mig),
  );
  push(
    "enroll raises NOT_ACTIVE",
    /fn_sponsorship_enroll_athlete[\s\S]{0,1200}RAISE EXCEPTION 'NOT_ACTIVE' USING ERRCODE = 'P0003'/.test(mig),
  );
  push(
    "enroll raises MEMBERSHIP_REQUIRED",
    /RAISE EXCEPTION 'MEMBERSHIP_REQUIRED' USING ERRCODE = '42501'/.test(mig),
  );
  push(
    "enroll idempotent via ON CONFLICT",
    /ON CONFLICT \(sponsorship_id, user_id\) DO UPDATE\s+SET opted_out_at = NULL/.test(mig),
  );

  push(
    "defines fn_sponsorship_opt_out_athlete",
    /CREATE OR REPLACE FUNCTION public\.fn_sponsorship_opt_out_athlete/.test(mig),
  );
  push(
    "opt_out only touches rows still active",
    /opted_out_at = now\(\)[\s\S]{0,200}opted_out_at IS NULL/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

// L22-02 correction — MUST drop the coin-distribution path.
const correctionPath = resolve(
  ROOT,
  "supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql",
);
const correction = safeRead(correctionPath, "L22-02 correction migration present");
if (correction) {
  push(
    "L22-02 drops fn_sponsorship_distribute_monthly_coins",
    /DROP FUNCTION IF EXISTS public\.fn_sponsorship_distribute_monthly_coins/.test(correction),
  );
  push(
    "L22-02 drops monthly_coins_per_athlete column",
    /DROP COLUMN IF EXISTS monthly_coins_per_athlete/.test(correction),
  );
  push(
    "L22-02 drops coin_budget_total column",
    /DROP COLUMN IF EXISTS coin_budget_total/.test(correction),
  );
  push(
    "L22-02 drops coin_budget_used column",
    /DROP COLUMN IF EXISTS coin_budget_used/.test(correction),
  );
  push(
    "L22-02 drops coin-budget CHECK constraints from sponsorships",
    /DROP CONSTRAINT IF EXISTS sponsorships_monthly_coins_nonneg[\s\S]{0,400}DROP CONSTRAINT IF EXISTS sponsorships_coin_budget_total_nonneg[\s\S]{0,400}DROP CONSTRAINT IF EXISTS sponsorships_coin_budget_used_nonneg[\s\S]{0,400}DROP CONSTRAINT IF EXISTS sponsorships_coin_budget_used_within/
      .test(correction),
  );
  push(
    "L22-02 deletes prior sponsorship_payout ledger rows",
    /DELETE FROM public\.coin_ledger[\s\S]{0,600}'sponsorship_payout'/.test(correction),
  );
  push(
    "L22-02 reason enum excludes sponsorship_payout",
    (() => {
      const m = correction.match(/ADD CONSTRAINT coin_ledger_reason_check CHECK \([\s\S]*?\);/);
      if (!m) return false;
      return !/sponsorship_payout/.test(m[0]);
    })(),
  );
  push(
    "L22-02 self-test asserts distribute function absent",
    /fn_sponsorship_distribute_monthly_coins should have been dropped/.test(correction),
  );
  push(
    "L22-02 self-test asserts monthly_coins column absent",
    /sponsorships\.monthly_coins_per_athlete should have been dropped/.test(correction),
  );
  push(
    "L22-02 runs in a single transaction",
    /^BEGIN;/m.test(correction) && /^COMMIT;/m.test(correction),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L16-05-integracoes-de-marcas-esportivas-sem-schema.md",
);
const finding = safeRead(findingPath, "L16-05 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421620000_l16_05_sponsorships\.sql/.test(finding),
  );
  push(
    "finding references L22-02 correction migration",
    /20260421700000_l22_02_revoke_nonchallenge_coins\.sql/.test(finding),
  );
  push(
    "finding references sponsorships + sponsorship_athletes",
    /sponsorships[\s\S]{0,400}sponsorship_athletes/.test(finding),
  );
  push(
    "finding documents challenge-only OmniCoin policy",
    /OmniCoin[^\n]{0,200}(desafio|challenge)/i.test(finding)
      || /(desafio|challenge)[^\n]{0,200}OmniCoin/i.test(finding),
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
  `\n${results.length - failed}/${results.length} sponsorships checks passed.`,
);
if (failed > 0) {
  console.error("\nL16-05 invariants broken.");
  process.exit(1);
}
