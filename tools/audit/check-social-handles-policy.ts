/**
 * check-social-handles-policy.ts
 *
 * L04-06 — CI guard for the social-handle policy primitives.
 *
 * Invariants:
 *   1. CHECK-bound format validator on `profiles.instagram_handle` and
 *      `profiles.tiktok_handle` via `fn_validate_social_handle`.
 *   2. `profiles.profile_public jsonb` added with default privacy-first
 *      payload + shape CHECK via `fn_validate_profile_public`.
 *   3. `profiles.social_handles_updated_at` timestamptz column exists.
 *   4. BEFORE UPDATE trigger `trg_profiles_social_handles_rate_limit`
 *      calls `fn_profiles_social_handles_rate_limit` on the two handle
 *      columns, enforces a configurable min-interval (default 86400 s),
 *      waives service_role, and audit-logs every accepted change.
 *   5. `fn_public_profile_view(uuid)` is STABLE + SECURITY DEFINER and
 *      returns handles only to self / platform_admin / when the owner
 *      toggled the matching `show_*` flag.
 *   6. Self-test asserts validator positives + negatives + profile_public
 *      shape.
 *   7. Grants pattern: helpers PUBLIC; public profile view authenticated +
 *      service_role + anon; REVOKE ALL FROM PUBLIC first.
 *   8. Migration runs in a single transaction.
 *   9. Finding cross-references the migration + accessor.
 *
 * Usage: npm run audit:social-handles-policy
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
  "supabase/migrations/20260421570000_l04_06_social_handles_policy.sql",
);
const mig = safeRead(migPath, "L04-06 migration present");
if (mig) {
  push(
    "defines fn_validate_social_handle (IMMUTABLE)",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_social_handle[\s\S]{0,300}IMMUTABLE/
      .test(mig),
  );
  push(
    "validator restricts to [A-Za-z0-9._]",
    /\[A-Za-z0-9\\._\]/.test(mig) || /\[A-Za-z0-9\._\]/.test(mig),
  );
  push(
    "validator caps length at 30",
    /length\(p_handle\) BETWEEN 1 AND 30/.test(mig),
  );
  push(
    "validator rejects http and bit.ly",
    /ILIKE '%http%'[\s\S]{0,200}ILIKE '%bit\.ly%'/.test(mig),
  );
  push(
    "CHECK on instagram_handle uses the validator",
    /profiles_instagram_handle_format[\s\S]{0,120}fn_validate_social_handle\(instagram_handle\)/
      .test(mig),
  );
  push(
    "CHECK on tiktok_handle uses the validator",
    /profiles_tiktok_handle_format[\s\S]{0,120}fn_validate_social_handle\(tiktok_handle\)/
      .test(mig),
  );

  push(
    "adds profiles.profile_public jsonb",
    /ADD COLUMN profile_public jsonb NOT NULL/.test(mig),
  );
  push(
    "profile_public defaults to all-false",
    /"show_instagram":false[\s\S]{0,80}"show_tiktok":false[\s\S]{0,80}"show_pace":false[\s\S]{0,80}"show_location":false/
      .test(mig),
  );
  push(
    "defines fn_validate_profile_public (IMMUTABLE)",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_profile_public[\s\S]{0,300}IMMUTABLE/
      .test(mig),
  );
  push(
    "profile_public shape checked via fn_validate_profile_public",
    /profiles_profile_public_shape[\s\S]{0,120}fn_validate_profile_public\(profile_public\)/
      .test(mig),
  );

  push(
    "adds profiles.social_handles_updated_at",
    /ADD COLUMN social_handles_updated_at timestamptz/.test(mig),
  );

  push(
    "defines fn_profiles_social_handles_rate_limit",
    /CREATE OR REPLACE FUNCTION public\.fn_profiles_social_handles_rate_limit/
      .test(mig),
  );
  push(
    "rate limit uses make_interval with min-interval GUC",
    /make_interval\(secs => v_min_interval_s\)/.test(mig),
  );
  push(
    "rate limit waives service_role",
    /current_setting\('role', true\) = 'service_role'[\s\S]{0,400}RETURN NEW/
      .test(mig),
  );
  push(
    "rate limit defaults to 24h",
    /COALESCE\(NULLIF\(v_setting, ''\)::integer, 86400\)/.test(mig),
  );
  push(
    "rate limit raises P0001 on violation",
    /social_handle\.rate_limited[\s\S]{0,400}ERRCODE = 'P0001'/.test(mig),
  );
  push(
    "accepted change inserts into portal_audit_log",
    /INSERT INTO public\.portal_audit_log[\s\S]{0,400}profile\.social_handle_changed/
      .test(mig),
  );
  push(
    "audit insert is fail-open",
    /RAISE WARNING 'L04-06: failed to write portal_audit_log social_handle_changed/
      .test(mig),
  );

  push(
    "attaches trg_profiles_social_handles_rate_limit trigger",
    /CREATE TRIGGER trg_profiles_social_handles_rate_limit[\s\S]{0,200}BEFORE UPDATE OF instagram_handle, tiktok_handle ON public\.profiles/
      .test(mig),
  );

  push(
    "defines fn_public_profile_view(uuid)",
    /CREATE OR REPLACE FUNCTION public\.fn_public_profile_view\(p_target uuid\)/
      .test(mig),
  );
  push(
    "fn_public_profile_view is STABLE SECURITY DEFINER",
    /fn_public_profile_view[\s\S]{0,400}STABLE[\s\S]{0,40}SECURITY DEFINER/
      .test(mig),
  );
  push(
    "owner / platform_admin bypass on instagram_handle",
    /v_self OR v_admin[\s\S]{0,120}show_instagram[\s\S]{0,60}v_row\.instagram_handle/
      .test(mig),
  );
  push(
    "owner / platform_admin bypass on tiktok_handle",
    /v_self OR v_admin[\s\S]{0,120}show_tiktok[\s\S]{0,60}v_row\.tiktok_handle/
      .test(mig),
  );
  push(
    "returns show_pace + show_location flags to consumer",
    /'show_pace'[\s\S]{0,80}'show_location'/.test(mig),
  );

  push(
    "self-test: validator accepts omni_runner",
    /fn_validate_social_handle must accept "omni_runner"/.test(mig),
  );
  push(
    "self-test: validator rejects bit.ly payloads",
    /fn_validate_social_handle must reject bit\.ly payloads/.test(mig),
  );
  push(
    "self-test: validator rejects http(s) payloads",
    /fn_validate_social_handle must reject http\(s\) payloads/.test(mig),
  );
  push(
    "self-test: validator rejects >30-char payloads",
    /must reject >30-char payloads/.test(mig),
  );
  push(
    "self-test: validator rejects whitespace",
    /fn_validate_social_handle must reject whitespace/.test(mig),
  );
  push(
    "self-test: validator rejects slashes",
    /fn_validate_social_handle must reject slashes/.test(mig),
  );
  push(
    "self-test: profile_public rejects wrong types",
    /fn_validate_profile_public must reject wrong type/.test(mig),
  );
  push(
    "self-test: profile_public rejects missing keys",
    /fn_validate_profile_public must reject missing keys/.test(mig),
  );

  push(
    "grants fn_public_profile_view to authenticated/service_role/anon",
    /GRANT\s+EXECUTE ON FUNCTION public\.fn_public_profile_view\(uuid\)[\s\S]{0,140}authenticated, service_role, anon/
      .test(mig),
  );
  push(
    "revokes fn_public_profile_view from PUBLIC first",
    /REVOKE ALL ON FUNCTION public\.fn_public_profile_view\(uuid\) FROM PUBLIC/
      .test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L04-06-campo-instagram-handle-tiktok-handle-em-profiles-sem.md",
);
const finding = safeRead(findingPath, "L04-06 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421570000_l04_06_social_handles_policy\.sql/.test(finding),
  );
  push(
    "finding references public profile accessor",
    /fn_public_profile_view/.test(finding),
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
  `\n${results.length - failed}/${results.length} social-handles-policy checks passed.`,
);
if (failed > 0) {
  console.error("\nL04-06 invariants broken.");
  process.exit(1);
}
