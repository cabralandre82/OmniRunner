/**
 * check-referral-program.ts
 *
 * L15-02 — CI guard for the referral program primitives.
 *
 * Invariants:
 *   1. coin_ledger reason enum extended with `referral_referrer_reward`
 *      and `referral_referred_reward`.
 *   2. `public.referral_rewards_config` exists as a single-row config
 *      table with CHECK-bounded fields.
 *   3. `public.referrals` exists with expected columns, unique code
 *      index, unique-activated-per-user partial index, status
 *      state-machine CHECK, self-referral CHECK, and RLS policies.
 *   4. State-machine BEFORE UPDATE trigger enforces pending-only exits.
 *   5. `fn_generate_referral_code(int)` clamps to [6, 16] and excludes
 *      ambiguous characters (0/O/1/I).
 *   6. `fn_create_referral(text)` gates channel, enforces per-user cap,
 *      and stamps `expires_at = now() + ttl_days` from config.
 *   7. `fn_activate_referral(text)` enforces pending + not expired +
 *      not self + no prior activation, credits both parties, and
 *      attempts wallet bumps.
 *   8. `fn_expire_referrals()` sweeps pending past TTL and is
 *      service_role only.
 *   9. Self-test covers generator clamp + alphabet + reason-enum
 *      extension.
 *  10. Grants: authenticated can call create + activate; only
 *      service_role can call expire.
 *  11. Migration runs in a single transaction.
 *  12. Finding references migration + RPCs.
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
    "extends coin_ledger reason enum with referral rewards",
    /coin_ledger_reason_check[\s\S]{0,2000}referral_referrer_reward[\s\S]{0,200}referral_referred_reward/
      .test(mig),
  );

  push(
    "creates referral_rewards_config (single-row)",
    /CREATE TABLE IF NOT EXISTS public\.referral_rewards_config[\s\S]{0,200}id\s+smallint PRIMARY KEY CHECK \(id = 1\)/
      .test(mig),
  );
  push(
    "config CHECKs reward + ttl + cap ranges",
    /reward_referrer_coins BETWEEN 0 AND 10000[\s\S]{0,400}ttl_days BETWEEN 1 AND 365[\s\S]{0,200}max_activations_per_user BETWEEN 1 AND 100000/
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
    "fn_activate_referral guards status not pending",
    /referral_not_pending[\s\S]{0,80}ERRCODE = 'P0001'/.test(mig),
  );
  push(
    "fn_activate_referral flips expired pending rows on detection",
    /status = 'expired', expired_at = v_now[\s\S]{0,200}referral_expired/.test(
      mig,
    ),
  );
  push(
    "fn_activate_referral blocks self-referral",
    /self_referral_blocked/.test(mig),
  );
  push(
    "fn_activate_referral blocks double-activation",
    /already_activated_referral/.test(mig),
  );
  push(
    "fn_activate_referral writes two coin_ledger rows",
    /INSERT INTO public\.coin_ledger[\s\S]{0,800}referral_referrer_reward[\s\S]{0,200}referral_referred_reward/
      .test(mig),
  );
  push(
    "fn_activate_referral bumps wallets best-effort",
    /UPDATE public\.wallets[\s\S]{0,400}balance_coins \+ v_row\.reward_referrer_coins[\s\S]{0,600}RAISE WARNING 'L15-02: wallet bump failed/
      .test(mig),
  );
  push(
    "fn_activate_referral uses FOR UPDATE on claim",
    /WHERE referral_code = upper\(p_code\)[\s\S]{0,40}FOR UPDATE/.test(mig),
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
    "self-test: generator length respected",
    /fn_generate_referral_code must emit exactly 8 chars/.test(mig),
  );
  push(
    "self-test: generator alphabet respected",
    /fn_generate_referral_code must emit only \[A-Z2-9\] chars/.test(mig),
  );
  push(
    "self-test: generator length clamp asserted",
    /fn_generate_referral_code must clamp p_len=4 to 6/.test(mig),
  );
  push(
    "self-test: reason enum extended asserted",
    /coin_ledger_reason_check must include referral_\* reasons/.test(mig),
  );
  push(
    "self-test: config seeded asserted",
    /referral_rewards_config\(id=1\) missing/.test(mig),
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
    "finding references fn_create_referral / fn_activate_referral",
    /fn_create_referral[\s\S]{0,400}fn_activate_referral/.test(finding),
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
