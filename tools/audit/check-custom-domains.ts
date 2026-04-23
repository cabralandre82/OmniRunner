/**
 * check-custom-domains.ts
 *
 * L16-02 — CI guard for custom-domain-per-group primitives.
 *
 * Invariants:
 *   1. `fn_validate_custom_host(text)` IMMUTABLE PARALLEL SAFE;
 *      rejects omnirunner.*, URL schemes, underscores, short TLD.
 *   2. `fn_generate_custom_domain_token()` returns 32-hex.
 *   3. `public.coaching_group_domains` exists with status CHECK,
 *      verification_token CHECK, RLS enabled, global UNIQUE(host),
 *      partial UNIQUE(group_id) where is_primary+verified, and
 *      references `coaching_groups` / `auth.users`.
 *   4. BEFORE INSERT/UPDATE trigger lower-cases host.
 *   5. AFTER INSERT + AFTER UPDATE OF trigger appends to
 *      `portal_audit_log` (fail-open).
 *   6. Register / mark_verified / mark_failed / revoke / resolve
 *      RPCs: correct security model (SECURITY DEFINER), correct
 *      grants, correct error codes (42501/P0001/P0002).
 *   7. Self-test covers 6 validator cases + 2 token cases.
 *   8. Migration runs in a single transaction.
 *   9. Finding references migration and fn_custom_domain_resolve.
 *
 * Usage: npm run audit:custom-domains
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
  "supabase/migrations/20260421600000_l16_02_custom_domains.sql",
);
const mig = safeRead(migPath, "L16-02 migration file present");

if (mig) {
  // Validators.
  push(
    "defines fn_validate_custom_host IMMUTABLE PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_custom_host[\s\S]{0,400}IMMUTABLE[\s\S]{0,120}PARALLEL SAFE/.test(mig),
  );
  push(
    "host validator rejects omnirunner apex",
    /omnirunner\[\.\]/.test(mig),
  );
  push(
    "host validator rejects URL-with-scheme",
    /\^https\?:\/\//.test(mig),
  );
  push(
    "host validator enforces RFC 1035-style regex",
    /\^\(\[a-z0-9\]\(\[a-z0-9-\]\{0,61\}\[a-z0-9\]\)\?\\\.\)\+\[a-z\]\{2,\}\$/.test(mig),
  );
  push(
    "host validator enforces length 4..253",
    /v_len < 4 OR v_len > 253/.test(mig),
  );
  push(
    "grants host validator to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_validate_custom_host\(TEXT\) TO PUBLIC/.test(mig),
  );

  // Token generator.
  push(
    "defines fn_generate_custom_domain_token",
    /CREATE OR REPLACE FUNCTION public\.fn_generate_custom_domain_token/.test(mig),
  );
  push(
    "token uses gen_random_bytes(16) hex-encoded",
    /encode\(gen_random_bytes\(16\), 'hex'\)/.test(mig),
  );

  // Table.
  push(
    "creates coaching_group_domains table",
    /CREATE TABLE IF NOT EXISTS public\.coaching_group_domains/.test(mig),
  );
  push(
    "table references coaching_groups with ON DELETE CASCADE",
    /group_id\s+UUID NOT NULL REFERENCES public\.coaching_groups\(id\) ON DELETE CASCADE/.test(mig),
  );
  push(
    "table has status CHECK enum",
    /CHECK \(status IN \('pending','verifying','verified','failed','revoked'\)\)/.test(mig),
  );
  push(
    "table CHECK constrains host via validator",
    /CONSTRAINT coaching_group_domains_host_shape CHECK \(public\.fn_validate_custom_host\(host\)\)/.test(mig),
  );
  push(
    "table CHECK constrains verification_token shape",
    /CONSTRAINT coaching_group_domains_token_shape CHECK \(verification_token ~ '\^\[0-9a-f\]\{32\}\$'\)/.test(mig),
  );
  push(
    "table CHECK constrains last_error length",
    /CONSTRAINT coaching_group_domains_last_error_len CHECK \(last_error IS NULL OR length\(last_error\) <= 500\)/.test(mig),
  );
  push(
    "table CHECK ties verified status to verified_at",
    /status = 'verified' AND verified_at IS NOT NULL/.test(mig),
  );
  push(
    "global UNIQUE index on host",
    /CREATE UNIQUE INDEX IF NOT EXISTS coaching_group_domains_host_unique[\s\S]{0,120}\(host\)/.test(mig),
  );
  push(
    "partial UNIQUE index on group_id for primary+verified",
    /CREATE UNIQUE INDEX IF NOT EXISTS coaching_group_domains_one_primary_per_group[\s\S]{0,200}WHERE is_primary = TRUE AND status = 'verified'/.test(mig),
  );

  // RLS.
  push(
    "ENABLE ROW LEVEL SECURITY on coaching_group_domains",
    /ALTER TABLE public\.coaching_group_domains ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "admin-read policy gates on platform_role=admin or admin_master",
    /coaching_group_domains_admin_read[\s\S]{0,400}platform_role = 'admin'[\s\S]{0,400}role = 'admin_master'/.test(mig),
  );

  // Triggers.
  push(
    "defines fn_coaching_group_domains_normalize",
    /CREATE OR REPLACE FUNCTION public\.fn_coaching_group_domains_normalize/.test(mig),
  );
  push(
    "normalize trigger lower-cases host",
    /NEW\.host := lower\(trim\(NEW\.host\)\)/.test(mig),
  );
  push(
    "BEFORE INSERT OR UPDATE trigger attached",
    /CREATE TRIGGER coaching_group_domains_normalize[\s\S]{0,200}BEFORE INSERT OR UPDATE OF host ON public\.coaching_group_domains/.test(mig),
  );
  push(
    "defines fn_coaching_group_domains_audit",
    /CREATE OR REPLACE FUNCTION public\.fn_coaching_group_domains_audit/.test(mig),
  );
  push(
    "audit trigger writes to portal_audit_log",
    /INSERT INTO public\.portal_audit_log[\s\S]{0,600}group\.custom_domain\.registered/.test(mig),
  );
  push(
    "audit trigger is fail-open",
    /EXCEPTION WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING 'coaching_group_domains audit failed/.test(mig),
  );
  push(
    "AFTER INSERT audit trigger attached",
    /CREATE TRIGGER coaching_group_domains_audit_insert[\s\S]{0,200}AFTER INSERT ON public\.coaching_group_domains/.test(mig),
  );
  push(
    "AFTER UPDATE OF audit trigger attached",
    /CREATE TRIGGER coaching_group_domains_audit_update[\s\S]{0,300}AFTER UPDATE OF status, is_primary, last_error ON public\.coaching_group_domains/.test(mig),
  );

  // RPCs.
  push(
    "defines fn_custom_domain_register",
    /CREATE OR REPLACE FUNCTION public\.fn_custom_domain_register/.test(mig),
  );
  push(
    "register is SECURITY DEFINER",
    /fn_custom_domain_register[\s\S]{0,600}SECURITY DEFINER/.test(mig),
  );
  push(
    "register raises INVALID_HOST for bad hostnames",
    /RAISE EXCEPTION 'INVALID_HOST' USING ERRCODE = 'P0001'/.test(mig),
  );
  push(
    "register raises FORBIDDEN 42501 for non-admin",
    /fn_custom_domain_register[\s\S]{0,2000}RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'/.test(mig),
  );
  push(
    "register waives for service_role",
    /fn_custom_domain_register[\s\S]{0,2000}current_setting\('role', true\) = 'service_role'/.test(mig),
  );
  push(
    "register grants to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_custom_domain_register\(UUID, TEXT, BOOLEAN\) TO authenticated, service_role/.test(mig),
  );
  push(
    "register revokes from PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_custom_domain_register\(UUID, TEXT, BOOLEAN\) FROM PUBLIC/.test(mig),
  );

  push(
    "defines fn_custom_domain_mark_verified",
    /CREATE OR REPLACE FUNCTION public\.fn_custom_domain_mark_verified\(p_host TEXT\)/.test(mig),
  );
  push(
    "mark_verified is service-role-only",
    /fn_custom_domain_mark_verified[\s\S]{0,600}current_setting\('role', true\) <> 'service_role'[\s\S]{0,200}SERVICE_ROLE_ONLY/.test(mig),
  );
  push(
    "mark_verified grants to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_custom_domain_mark_verified\(TEXT\) TO service_role/.test(mig),
  );

  push(
    "defines fn_custom_domain_mark_failed",
    /CREATE OR REPLACE FUNCTION public\.fn_custom_domain_mark_failed/.test(mig),
  );
  push(
    "mark_failed clamps last_error to 500 chars",
    /LEFT\(COALESCE\(p_reason, ''\), 500\)/.test(mig),
  );

  push(
    "defines fn_custom_domain_revoke",
    /CREATE OR REPLACE FUNCTION public\.fn_custom_domain_revoke/.test(mig),
  );
  push(
    "revoke clears is_primary when revoking",
    /UPDATE public\.coaching_group_domains[\s\S]{0,400}is_primary = FALSE[\s\S]{0,200}revoked/.test(mig),
  );

  push(
    "defines fn_custom_domain_resolve (STABLE SECURITY DEFINER)",
    /CREATE OR REPLACE FUNCTION public\.fn_custom_domain_resolve[\s\S]{0,600}STABLE[\s\S]{0,120}SECURITY DEFINER/.test(mig),
  );
  push(
    "resolve only returns rows with status=verified",
    /fn_custom_domain_resolve[\s\S]{0,600}status = 'verified'/.test(mig),
  );
  push(
    "resolve joins portal_branding for branding_enabled",
    /SELECT branding_enabled INTO v_branding_enabled[\s\S]{0,200}FROM public\.portal_branding/.test(mig),
  );
  push(
    "resolve grants to anon + authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_custom_domain_resolve\(TEXT\) TO anon, authenticated, service_role/.test(mig),
  );

  // Self-test.
  push(
    "self-test: validator rejects omnirunner apex",
    /self-test: fn_validate_custom_host accepted omnirunner apex/.test(mig),
  );
  push(
    "self-test: validator rejects URL-with-scheme",
    /self-test: fn_validate_custom_host accepted URL-with-scheme/.test(mig),
  );
  push(
    "self-test: validator rejects underscore",
    /self-test: fn_validate_custom_host accepted underscore/.test(mig),
  );
  push(
    "self-test: validator rejects short tld",
    /self-test: fn_validate_custom_host accepted short tld/.test(mig),
  );
  push(
    "self-test: token length asserted",
    /self-test: token length must be 32 hex chars/.test(mig),
  );
  push(
    "self-test: token hex asserted",
    /self-test: token must be hex/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L16-02-sem-custom-domain-por-assessoria.md",
);
const finding = safeRead(findingPath, "L16-02 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421600000_l16_02_custom_domains\.sql/.test(finding),
  );
  push(
    "finding references fn_custom_domain_resolve",
    /fn_custom_domain_resolve/.test(finding),
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
  `\n${results.length - failed}/${results.length} custom-domains checks passed.`,
);
if (failed > 0) {
  console.error("\nL16-02 invariants broken.");
  process.exit(1);
}
