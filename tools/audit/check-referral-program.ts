/**
 * check-referral-program.ts
 *
 * L15-02 — CI guard for the referral program primitives.
 *
 * Corrected by L22-02 (2026-04-21): OmniCoins are earned only inside
 * challenges; referral activation MUST NOT credit coins or bump wallets.
 * The referral table is retained for viral-growth tracking only.
 *
 * Invariants:
 *   1. `public.referral_rewards_config` exists as a single-row config
 *      table bounded on code_length / ttl_days / max_activations_per_user.
 *      It must NOT contain coin-reward columns.
 *   2. `public.referrals` exists with FKs, channel enum, status CHECK,
 *      self-referral CHECK, and the activated-has-referred CHECK.  It
 *      must NOT contain coin-reward columns.
 *   3. State-machine BEFORE UPDATE trigger enforces pending-only exits.
 *   4. `fn_generate_referral_code(int)` clamps len to [6, 16] and
 *      excludes ambiguous characters (0/O/1/I).
 *   5. `fn_create_referral(text)` gates channel, enforces per-user cap,
 *      and stamps expires_at from config ttl_days.
 *   6. `fn_activate_referral(text)` flips status to 'activated' and
 *      must NOT insert into coin_ledger or mutate wallets.balance_coins.
 *   7. `fn_expire_referrals()` sweeps pending past TTL, service_role only.
 *   8. L22-02 correction migration drops the reward columns and
 *      removes the reward reasons from coin_ledger_reason_check.
 *   9. L22-02 correction migration replaces fn_activate_referral with
 *      a version free of ledger / wallet mutations.
 *  10. Grants: authenticated can call create + activate; only
 *      service_role can call expire.
 *  11. Both migrations run in a single transaction.
 *  12. Finding references both migrations + RPCs.
 *
 * Usage: npm run audit:referral-program
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
  "supabase/migrations/20260421580000_l15_02_referral_program.sql",
);
const mig = safeRead(migPath, "L15-02 migration present");
if (mig) {
  push(
    "creates referral_rewards_config (single-row)",
    /CREATE TABLE IF NOT EXISTS public\.referral_rewards_config[\s\S]{0,200}id\s+smallint PRIMARY KEY CHECK \(id = 1\)/
      .test(mig),
  );
  push(
    "config CHECKs ttl + cap ranges",
    /ttl_days BETWEEN 1 AND 365[\s\S]{0,200}max_activations_per_user BETWEEN 1 AND 100000/
      .test(mig),
  );
  push(
    "config seeded with id=1",
    /INSERT INTO public\.referral_rewards_config \(id\) VALUES \(1\)[\s\S]{0,60}ON CONFLICT \(id\) DO NOTHING/
      .test(mig),
  );

  push(
    "creates referrals table with FKs",
    /CREATE TABLE IF NOT EXISTS public\.referrals[\s\S]{0,400}referrer_user_id\s+uuid NOT NULL REFERENCES auth\.users\(id\) ON DELETE CASCADE/
      .test(mig),
  );
  push(
    "referred_user_id FK ON DELETE SET NULL",
    /referred_user_id\s+uuid REFERENCES auth\.users\(id\) ON DELETE SET NULL/
      .test(mig),
  );
  push(
    "referrals channel CHECK enum",
    /channel[\s\S]{0,200}CHECK \(channel IN \('link','whatsapp','instagram','tiktok','email','sms','qr'\)\)/
      .test(mig),
  );
  push(
    "referrals status state-machine CHECK",
    /CHECK \(status IN \('pending','activated','expired','revoked'\)\)/.test(
      mig,
    ),
  );
  push(
    "self-referral blocked by CHECK",
    /referrals_self_referral_blocked[\s\S]{0,200}referred_user_id <> referrer_user_id/
      .test(mig),
  );
  push(
    "status timestamps CHECK is exhaustive",
    /referrals_status_timestamps[\s\S]{0,800}status = 'pending'[\s\S]{0,400}status = 'activated'[\s\S]{0,200}status = 'expired'[\s\S]{0,200}status = 'revoked'/
      .test(mig),
  );
  push(
    "activated rows must have referred_user_id",
    /referrals_activated_has_referred[\s\S]{0,200}status <> 'activated' OR referred_user_id IS NOT NULL/
      .test(mig),
  );

  push(
    "unique index on referral_code",
    /CREATE UNIQUE INDEX IF NOT EXISTS uniq_referrals_code[\s\S]{0,120}referral_code/
      .test(mig),
  );
  push(
    "unique partial index on referred_user_id for activated",
    /CREATE UNIQUE INDEX IF NOT EXISTS uniq_referrals_referred_once[\s\S]{0,200}WHERE status = 'activated'/
      .test(mig),
  );
  push(
    "pending-expiry partial index",
    /idx_referrals_pending_expiry[\s\S]{0,200}WHERE status = 'pending'/.test(
      mig,
    ),
  );

  push(
    "RLS enabled on referrals",
    /ALTER TABLE public\.referrals ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "RLS: own read (referrer or referred)",
    /referrals_own_read[\s\S]{0,300}auth\.uid\(\) = referrer_user_id OR auth\.uid\(\) = referred_user_id/
      .test(mig),
  );
  push(
    "RLS: admin read",
    /referrals_admin_read[\s\S]{0,300}platform_role = 'admin'/.test(mig),
  );

  push(
    "status-guard trigger enforces pending-only exits",
    /fn_referrals_status_guard[\s\S]{0,600}OLD\.status = 'pending' AND NEW\.status IN \('activated','expired','revoked'\)/
      .test(mig),
  );
  push(
    "status-guard trigger raises INVALID_TRANSITION",
    /INVALID_TRANSITION[\s\S]{0,200}ERRCODE = 'P0001'/.test(mig),
  );

  push(
    "fn_generate_referral_code clamps len to [6, 16]",
    /GREATEST\(6, LEAST\(16, COALESCE\(p_len, 8\)\)\)/.test(mig),
  );
  push(
    "generator excludes ambiguous chars (0/O/1/I)",
    /ABCDEFGHJKLMNPQRSTUVWXYZ23456789/.test(mig),
  );
  push(
    "generator retries on collision (max 8) and raises P0002",
    /v_tries > 8[\s\S]{0,200}referral_code_generation_exhausted[\s\S]{0,80}ERRCODE = 'P0002'/
      .test(mig),
  );

  push(
    "fn_create_referral rejects unauthenticated",
    /fn_create_referral[\s\S]{0,800}unauthenticated[\s\S]{0,80}ERRCODE = '42501'/
      .test(mig),
  );
  push(
    "fn_create_referral validates channel enum",
    /p_channel NOT IN \('link','whatsapp','instagram','tiktok','email','sms','qr'\)/
      .test(mig),
  );
  push(
    "fn_create_referral enforces per-referrer cap",
    /referral_cap_reached[\s\S]{0,200}ERRCODE = 'P0003'/.test(mig),
  );
  push(
    "fn_create_referral stamps expires_at from config ttl_days",
    /now\(\) \+ make_interval\(days => v_cfg\.ttl_days\)/.test(mig),
  );

  push(
    "fn_expire_referrals is service_role only",
    /fn_expire_referrals[\s\S]{0,400}service_role required[\s\S]{0,80}ERRCODE = '42501'/
      .test(mig),
  );
  push(
    "fn_expire_referrals returns count",
    /SELECT count\(\*\)::integer INTO v_count FROM expired/.test(mig),
  );

  push(
    "grants fn_create_referral to authenticated + service_role",
    /GRANT\s+EXECUTE ON FUNCTION public\.fn_create_referral\(text\)[\s\S]{0,120}authenticated, service_role/
      .test(mig),
  );
  push(
    "grants fn_activate_referral to authenticated + service_role",
    /GRANT\s+EXECUTE ON FUNCTION public\.fn_activate_referral\(text\)[\s\S]{0,120}authenticated, service_role/
      .test(mig),
  );
  push(
    "grants fn_expire_referrals to service_role only",
    /GRANT\s+EXECUTE ON FUNCTION public\.fn_expire_referrals\(\)\s+TO service_role/
      .test(mig),
  );
  push(
    "revokes mutating RPCs from PUBLIC first",
    /REVOKE ALL ON FUNCTION public\.fn_create_referral\(text\)\s+FROM PUBLIC[\s\S]{0,300}REVOKE ALL ON FUNCTION public\.fn_activate_referral\(text\) FROM PUBLIC/
      .test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

// L22-02 correction migration neutralises the coin-credit path.
const correctionPath = resolve(
  ROOT,
  "supabase/migrations/20260421700000_l22_02_revoke_nonchallenge_coins.sql",
);
const correction = safeRead(correctionPath, "L22-02 correction migration present");
if (correction) {
  push(
    "L22-02 drops referral reward columns from referrals",
    /ALTER TABLE public\.referrals[\s\S]{0,400}DROP COLUMN IF EXISTS reward_referrer_coins[\s\S]{0,200}DROP COLUMN IF EXISTS reward_referred_coins/
      .test(correction),
  );
  push(
    "L22-02 drops referral reward columns from config",
    /ALTER TABLE public\.referral_rewards_config[\s\S]{0,400}DROP COLUMN IF EXISTS reward_referrer_coins[\s\S]{0,200}DROP COLUMN IF EXISTS reward_referred_coins/
      .test(correction),
  );
  push(
    "L22-02 deletes prior referral reward ledger rows",
    /DELETE FROM public\.coin_ledger[\s\S]{0,400}'referral_referrer_reward'[\s\S]{0,200}'referral_referred_reward'/
      .test(correction),
  );
  push(
    "L22-02 replaces fn_activate_referral (no coin insert, no wallet bump)",
    /CREATE OR REPLACE FUNCTION public\.fn_activate_referral\([^\)]*text[^\)]*\)[\s\S]{0,4000}Intentionally NO coin_ledger insert/
      .test(correction),
  );
  push(
    "L22-02 new fn_activate_referral body has NO coin_ledger insert",
    (() => {
      const m = correction.match(/CREATE OR REPLACE FUNCTION public\.fn_activate_referral[\s\S]*?\$\$;/);
      if (!m) return false;
      return !/INSERT INTO public\.coin_ledger/i.test(m[0])
          && !/UPDATE public\.wallets[\s\S]{0,200}balance_coins/i.test(m[0]);
    })(),
  );
  push(
    "L22-02 canonical reason enum excludes referral_* rewards",
    (() => {
      const m = correction.match(/ADD CONSTRAINT coin_ledger_reason_check CHECK \([\s\S]*?\);/);
      if (!m) return false;
      return !/referral_referrer_reward/.test(m[0])
          && !/referral_referred_reward/.test(m[0])
          && !/referral_bonus/.test(m[0]);
    })(),
  );
  push(
    "L22-02 self-test asserts forbidden reasons absent",
    /forbidden non-challenge reason still present/.test(correction),
  );
  push(
    "L22-02 self-test asserts fn_activate_referral does NOT credit coins",
    /fn_activate_referral still credits coins \/ bumps wallet/.test(correction),
  );
  push(
    "L22-02 runs in a single transaction",
    /^BEGIN;/m.test(correction) && /^COMMIT;/m.test(correction),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L15-02-sem-sistema-de-referral-convite-viral.md",
);
const finding = safeRead(findingPath, "L15-02 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421580000_l15_02_referral_program\.sql/.test(finding),
  );
  push(
    "finding references L22-02 correction migration",
    /20260421700000_l22_02_revoke_nonchallenge_coins\.sql/.test(finding),
  );
  push(
    "finding references fn_create_referral / fn_activate_referral",
    /fn_create_referral[\s\S]{0,400}fn_activate_referral/.test(finding),
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
  `\n${results.length - failed}/${results.length} referral-program checks passed.`,
);
if (failed > 0) {
  console.error("\nL15-02 invariants broken.");
  process.exit(1);
}
