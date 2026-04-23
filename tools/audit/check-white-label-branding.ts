/**
 * check-white-label-branding.ts
 *
 * L16-01 — CI guard for white-label branding primitives.
 *
 * Invariants:
 *   1. portal_branding gains brand_name / subtitle / logo_url_dark /
 *      favicon_url / branding_enabled / updated_by / version columns
 *      (additive, idempotent).
 *   2. IMMUTABLE helpers fn_validate_hex_color and fn_validate_https_url
 *      exist, are PARALLEL SAFE, and accept NULL (documented NULL-safe).
 *   3. CHECK constraints use the validators for each colour / URL /
 *      brand_name / subtitle column.
 *   4. BEFORE UPDATE trigger fn_portal_branding_version_bump bumps
 *      version, stamps updated_by, and appends to portal_audit_log with
 *      fail-open audit.
 *   5. Public viewer-scoped accessor fn_group_branding_public returns
 *      NULL when branding_enabled is false and is granted to
 *      anon/authenticated/service_role.
 *   6. Admin RPC fn_group_branding_set gates on admin_master
 *      membership or platform_role='admin', raises 42501 otherwise,
 *      and is NOT granted to anon/PUBLIC.
 *   7. Self-test block covers hex colour + https URL validators.
 *   8. Migration runs in a single transaction.
 *   9. Finding document references the migration and the public
 *      accessor.
 *
 * Usage: npm run audit:white-label-branding
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
  "supabase/migrations/20260421590000_l16_01_white_label_branding.sql",
);
const mig = safeRead(migPath, "L16-01 migration file present");

if (mig) {
  push(
    "adds brand_name column (idempotent)",
    /ADD COLUMN IF NOT EXISTS brand_name TEXT/.test(mig),
  );
  push(
    "adds subtitle column",
    /ADD COLUMN IF NOT EXISTS subtitle TEXT/.test(mig),
  );
  push(
    "adds logo_url_dark column",
    /ADD COLUMN IF NOT EXISTS logo_url_dark TEXT/.test(mig),
  );
  push(
    "adds favicon_url column",
    /ADD COLUMN IF NOT EXISTS favicon_url TEXT/.test(mig),
  );
  push(
    "adds branding_enabled boolean default false",
    /ADD COLUMN IF NOT EXISTS branding_enabled BOOLEAN NOT NULL DEFAULT false/.test(mig),
  );
  push(
    "adds updated_by uuid",
    /ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth\.users\(id\)/.test(mig),
  );
  push(
    "adds version bigint default 0",
    /ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0/.test(mig),
  );

  push(
    "defines fn_validate_hex_color IMMUTABLE PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_hex_color[\s\S]{0,400}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(mig),
  );
  push(
    "hex validator accepts NULL (short-circuit)",
    /fn_validate_hex_color[\s\S]{0,400}IF p_value IS NULL THEN[\s\S]{0,120}RETURN TRUE/.test(mig),
  );
  push(
    "hex validator enforces 6-digit hex regex",
    /\^#\[0-9A-Fa-f\]\{6\}\$/.test(mig),
  );
  push(
    "defines fn_validate_https_url IMMUTABLE PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_https_url[\s\S]{0,400}IMMUTABLE[\s\S]{0,120}PARALLEL SAFE/.test(mig),
  );
  push(
    "https validator enforces https:// prefix",
    /\^https:\/\//.test(mig),
  );
  push(
    "https validator enforces max length",
    /length\(p_value\) > p_max_len/.test(mig),
  );
  push(
    "grants hex validator to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_validate_hex_color\(TEXT\) TO PUBLIC/.test(mig),
  );
  push(
    "grants https validator to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_validate_https_url\(TEXT, INT\) TO PUBLIC/.test(mig),
  );

  push(
    "drops old colour CHECKs before re-adding",
    /DROP CONSTRAINT IF EXISTS portal_branding_primary_color_hex/.test(mig),
  );
  push(
    "CHECK constraint on primary_color via validator",
    /CONSTRAINT portal_branding_primary_color_hex CHECK \(public\.fn_validate_hex_color\(primary_color\)\)/.test(mig),
  );
  push(
    "CHECK constraint on sidebar_bg via validator",
    /CONSTRAINT portal_branding_sidebar_bg_hex +CHECK \(public\.fn_validate_hex_color\(sidebar_bg\)\)/.test(mig),
  );
  push(
    "CHECK constraint on sidebar_text via validator",
    /CONSTRAINT portal_branding_sidebar_text_hex +CHECK \(public\.fn_validate_hex_color\(sidebar_text\)\)/.test(mig),
  );
  push(
    "CHECK constraint on accent_color via validator",
    /CONSTRAINT portal_branding_accent_color_hex +CHECK \(public\.fn_validate_hex_color\(accent_color\)\)/.test(mig),
  );
  push(
    "CHECK constraint on logo_url via validator",
    /CONSTRAINT portal_branding_logo_url_https +CHECK \(public\.fn_validate_https_url\(logo_url, 500\)\)/.test(mig),
  );
  push(
    "CHECK constraint on logo_url_dark via validator",
    /CONSTRAINT portal_branding_logo_url_dark_https CHECK \(public\.fn_validate_https_url\(logo_url_dark, 500\)\)/.test(mig),
  );
  push(
    "CHECK constraint on favicon_url via validator",
    /CONSTRAINT portal_branding_favicon_url_https CHECK \(public\.fn_validate_https_url\(favicon_url, 500\)\)/.test(mig),
  );
  push(
    "CHECK constraint on brand_name length 2..40",
    /CONSTRAINT portal_branding_brand_name_len[\s\S]{0,120}BETWEEN 2 AND 40/.test(mig),
  );
  push(
    "CHECK constraint on subtitle length <=120",
    /CONSTRAINT portal_branding_subtitle_len[\s\S]{0,120}length\(subtitle\) <= 120/.test(mig),
  );

  push(
    "defines fn_portal_branding_version_bump trigger function",
    /CREATE OR REPLACE FUNCTION public\.fn_portal_branding_version_bump/.test(mig),
  );
  push(
    "trigger bumps version on update",
    /NEW\.version := COALESCE\(OLD\.version, 0\) \+ 1/.test(mig),
  );
  push(
    "trigger stamps updated_by from auth.uid",
    /NEW\.updated_by := v_actor/.test(mig),
  );
  push(
    "trigger writes diff to portal_audit_log",
    /INSERT INTO public\.portal_audit_log[\s\S]{0,400}group\.branding\.updated/.test(mig),
  );
  push(
    "trigger is fail-open on audit errors",
    /EXCEPTION WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING 'portal_branding audit log failed/.test(mig),
  );
  push(
    "BEFORE UPDATE trigger attached",
    /CREATE TRIGGER portal_branding_version_bump[\s\S]{0,200}BEFORE UPDATE ON public\.portal_branding/.test(mig),
  );

  push(
    "defines fn_group_branding_public accessor",
    /CREATE OR REPLACE FUNCTION public\.fn_group_branding_public\(p_group_id UUID\)/.test(mig),
  );
  push(
    "public accessor is STABLE SECURITY DEFINER",
    /fn_group_branding_public[\s\S]{0,600}STABLE[\s\S]{0,120}SECURITY DEFINER/.test(mig),
  );
  push(
    "public accessor returns NULL when branding disabled",
    /IF NOT FOUND OR v_row\.branding_enabled IS DISTINCT FROM TRUE THEN[\s\S]{0,80}RETURN NULL/.test(mig),
  );
  push(
    "public accessor grants to anon + authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_group_branding_public\(UUID\) TO anon, authenticated, service_role/.test(mig),
  );
  push(
    "public accessor revokes from PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_group_branding_public\(UUID\) FROM PUBLIC/.test(mig),
  );

  push(
    "defines fn_group_branding_set admin RPC",
    /CREATE OR REPLACE FUNCTION public\.fn_group_branding_set\(\s*p_group_id UUID,\s*p_payload JSONB\s*\)/.test(mig),
  );
  push(
    "admin RPC is SECURITY DEFINER",
    /fn_group_branding_set[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "admin RPC waives for service_role",
    /current_setting\('role', true\) = 'service_role'[\s\S]{0,200}v_is_admin := TRUE/.test(mig),
  );
  push(
    "admin RPC gates on admin_master membership or platform_admin",
    /coaching_members[\s\S]{0,400}role = 'admin_master'/.test(mig)
      && /platform_role = 'admin'/.test(mig),
  );
  push(
    "admin RPC raises 42501 for forbidden",
    /IF NOT v_is_admin THEN[\s\S]{0,120}RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'/.test(mig),
  );
  push(
    "admin RPC upserts via ON CONFLICT (group_id)",
    /ON CONFLICT \(group_id\) DO UPDATE SET/.test(mig),
  );
  push(
    "admin RPC grants to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_group_branding_set\(UUID, JSONB\) TO authenticated, service_role/.test(mig),
  );
  push(
    "admin RPC revokes from PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_group_branding_set\(UUID, JSONB\) FROM PUBLIC/.test(mig),
  );

  push(
    "self-test asserts hex validator rejects short value",
    /self-test: fn_validate_hex_color accepted short value/.test(mig),
  );
  push(
    "self-test asserts hex validator rejects named colour",
    /self-test: fn_validate_hex_color accepted named colour/.test(mig),
  );
  push(
    "self-test asserts https validator rejects http",
    /self-test: fn_validate_https_url accepted http URL/.test(mig),
  );
  push(
    "self-test asserts https validator rejects javascript scheme",
    /self-test: fn_validate_https_url accepted javascript: scheme/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L16-01-sem-white-label-branding-customizado-por-grupo.md",
);
const finding = safeRead(findingPath, "L16-01 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421590000_l16_01_white_label_branding\.sql/.test(finding),
  );
  push(
    "finding references public accessor",
    /fn_group_branding_public/.test(finding),
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
  `\n${results.length - failed}/${results.length} white-label-branding checks passed.`,
);
if (failed > 0) {
  console.error("\nL16-01 invariants broken.");
  process.exit(1);
}
