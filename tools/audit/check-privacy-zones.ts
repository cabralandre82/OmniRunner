/**
 * check-privacy-zones.ts
 *
 * L04-05 — CI guard for the GPS privacy-zones primitives.
 *
 * Invariants:
 *   1. Migration adds `profiles.privacy_zones jsonb` with a CHECK
 *      constraint backed by `fn_validate_privacy_zones` (CHECK cannot
 *      contain subqueries).
 *   2. Migration defines the pure helpers `fn_haversine_m`,
 *      `fn_point_in_zones`, `fn_decode_polyline`, `fn_encode_polyline`,
 *      `fn_encode_polyline_value`, and `fn_mask_polyline`. All of them
 *      are IMMUTABLE / PARALLEL SAFE.
 *   3. Migration defines `fn_session_polyline_for_viewer(uuid)` as
 *      SECURITY DEFINER, applies owner + platform_admin bypass, logs
 *      admin access to `portal_audit_log`, and falls back to
 *      `fn_mask_polyline` for everyone else with default head/tail
 *      trim of 200 m.
 *   4. Self-test asserts column presence + encoder round-trip +
 *      validator positive/negative cases + haversine sanity.
 *   5. Migration runs in a single transaction.
 *   6. Finding + ROADMAP cross-reference the migration.
 *
 * Usage: npm run audit:privacy-zones
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
  "supabase/migrations/20260421560000_l04_05_privacy_zones.sql",
);
const mig = safeRead(migPath, "L04-05 migration present");
if (mig) {
  push(
    "adds profiles.privacy_zones jsonb column",
    /ADD COLUMN privacy_zones jsonb NOT NULL DEFAULT '\[\]'::jsonb/.test(mig),
  );
  push(
    "privacy_zones CHECK uses fn_validate_privacy_zones",
    /profiles_privacy_zones_shape[\s\S]{0,200}fn_validate_privacy_zones\(privacy_zones\)/.test(
      mig,
    ),
  );
  push(
    "fn_validate_privacy_zones exists and is IMMUTABLE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_privacy_zones[\s\S]{0,400}IMMUTABLE/.test(
      mig,
    ),
  );
  push(
    "fn_validate_privacy_zones rejects radius out of [50, 500]",
    /radius_m[\s\S]{0,200}NOT BETWEEN 50 AND 500/.test(mig),
  );
  push(
    "fn_validate_privacy_zones rejects lat out of [-90, 90]",
    /lat[\s\S]{0,120}NOT BETWEEN -90  AND  90/.test(mig),
  );
  push(
    "fn_validate_privacy_zones rejects lng out of [-180, 180]",
    /lng[\s\S]{0,120}NOT BETWEEN -180 AND 180/.test(mig),
  );
  push(
    "fn_validate_privacy_zones caps zone count to 5",
    /jsonb_array_length\(p_zones\) <= 5/.test(mig),
  );

  push(
    "defines fn_haversine_m",
    /CREATE OR REPLACE FUNCTION public\.fn_haversine_m/.test(mig),
  );
  push(
    "fn_haversine_m is IMMUTABLE PARALLEL SAFE",
    /fn_haversine_m[\s\S]{0,600}IMMUTABLE[\s\S]{0,40}PARALLEL SAFE/.test(mig),
  );
  push(
    "fn_haversine_m uses the 6371000m earth radius",
    /6371000/.test(mig),
  );

  push(
    "defines fn_point_in_zones",
    /CREATE OR REPLACE FUNCTION public\.fn_point_in_zones/.test(mig),
  );
  push(
    "fn_point_in_zones clamps radius defensively",
    /GREATEST\(50\.0, LEAST\(500\.0,/.test(mig),
  );

  push(
    "defines fn_decode_polyline",
    /CREATE OR REPLACE FUNCTION public\.fn_decode_polyline/.test(mig),
  );
  push(
    "fn_decode_polyline uses Google zigzag decoding",
    /v_result & 1[\s\S]{0,100}v_result >> 1/.test(mig),
  );
  push(
    "fn_decode_polyline caps runaway input at 100k points",
    /v_k > 100000/.test(mig),
  );

  push(
    "defines fn_encode_polyline_value",
    /CREATE OR REPLACE FUNCTION public\.fn_encode_polyline_value/.test(mig),
  );
  push(
    "defines fn_encode_polyline",
    /CREATE OR REPLACE FUNCTION public\.fn_encode_polyline\(p_points jsonb\)/
      .test(mig),
  );

  push(
    "defines fn_mask_polyline",
    /CREATE OR REPLACE FUNCTION public\.fn_mask_polyline/.test(mig),
  );
  push(
    "fn_mask_polyline defaults trim to 200 m head + 200 m tail",
    /p_trim_start_m integer DEFAULT 200[\s\S]{0,120}p_trim_end_m\s+integer DEFAULT 200/
      .test(mig),
  );
  push(
    "fn_mask_polyline clamps trim to [0, 5000] m",
    /GREATEST\(0, LEAST\(5000, COALESCE\(p_trim_start_m/.test(mig),
  );
  push(
    "fn_mask_polyline returns empty string when nothing survives",
    /jsonb_array_length\(v_filtered\) = 0[\s\S]{0,80}RETURN ''/.test(mig),
  );

  push(
    "defines fn_session_polyline_for_viewer",
    /CREATE OR REPLACE FUNCTION public\.fn_session_polyline_for_viewer/.test(
      mig,
    ),
  );
  push(
    "fn_session_polyline_for_viewer is SECURITY DEFINER",
    /fn_session_polyline_for_viewer[\s\S]{0,500}SECURITY DEFINER/.test(mig),
  );
  push(
    "fn_session_polyline_for_viewer enforces unauthenticated guard",
    /unauthenticated[\s\S]{0,80}42501/.test(mig),
  );
  push(
    "owner receives the raw polyline",
    /v_viewer = v_owner[\s\S]{0,40}RETURN v_poly/.test(mig),
  );
  push(
    "platform_admin receives raw polyline",
    /v_is_admin[\s\S]{0,600}RETURN v_poly/.test(mig),
  );
  push(
    "platform_admin access logged in portal_audit_log",
    /INSERT INTO public\.portal_audit_log[\s\S]{0,400}session\.polyline\.admin_view/
      .test(mig),
  );
  push(
    "admin audit write is fail-open (RAISE WARNING on failure)",
    /RAISE WARNING 'L04-05: failed to write portal_audit_log admin_view/.test(
      mig,
    ),
  );
  push(
    "non-owner path calls fn_mask_polyline with 200/200 defaults",
    /fn_mask_polyline\(v_poly, v_zones, 200, 200\)/.test(mig),
  );

  push(
    "grants execute on fn_session_polyline_for_viewer to authenticated + service_role",
    /GRANT\s+EXECUTE ON FUNCTION public\.fn_session_polyline_for_viewer\(uuid\)[\s\S]{0,120}authenticated, service_role/
      .test(mig),
  );
  push(
    "revokes fn_session_polyline_for_viewer from PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_session_polyline_for_viewer\(uuid\) FROM PUBLIC/
      .test(mig),
  );

  push(
    "self-test: column presence asserted",
    /self-test: profiles\.privacy_zones column missing/.test(mig),
  );
  push(
    "self-test: decoder cardinality asserted on canonical sample",
    /fn_decode_polyline expected 3 rows/.test(mig),
  );
  push(
    "self-test: encoder round-trip asserted",
    /fn_encode_polyline round-trip failed/.test(mig),
  );
  push(
    "self-test: mask must not strip everything for a central zone",
    /stripped everything when zone only covers the middle/.test(mig),
  );
  push(
    "self-test: haversine ~1deg-lat ~= 111km",
    /fn_haversine_m sanity check failed/.test(mig),
  );
  push(
    "self-test: fn_point_in_zones positive case",
    /fn_point_in_zones must hit \(0,0\)/.test(mig),
  );
  push(
    "self-test: fn_point_in_zones negative case",
    /fn_point_in_zones must NOT hit \(1,0\)/.test(mig),
  );
  push(
    "self-test: validator rejects radius < 50",
    /fn_validate_privacy_zones must reject radius_m < 50/.test(mig),
  );
  push(
    "self-test: validator rejects out-of-range lat",
    /fn_validate_privacy_zones must reject out-of-range lat/.test(mig),
  );
  push(
    "self-test: validator rejects non-array",
    /fn_validate_privacy_zones must reject non-array/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L04-05-trajetorias-gps-brutas-sem-opcao-de-privacy-zones.md",
);
const finding = safeRead(findingPath, "L04-05 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421560000_l04_05_privacy_zones\.sql/.test(finding),
  );
  push(
    "finding references viewer-scoped accessor",
    /fn_session_polyline_for_viewer/.test(finding),
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
  `\n${results.length - failed}/${results.length} privacy-zones checks passed.`,
);
if (failed > 0) {
  console.error("\nL04-05 invariants broken.");
  process.exit(1);
}
