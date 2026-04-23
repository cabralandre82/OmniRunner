/**
 * check-geofenced-checkin.ts
 *
 * L23-08 — CI guard for geofenced auto-check-in primitives.
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
  "supabase/migrations/20260421660000_l23_08_geofenced_checkin.sql",
);
const mig = safeRead(migPath, "L23-08 migration present");

if (mig) {
  // Session columns.
  push(
    "adds location_radius_meters column",
    /ADD COLUMN IF NOT EXISTS location_radius_meters INT/.test(mig),
  );
  push(
    "adds checkin_early_seconds default 1800",
    /checkin_early_seconds INT NOT NULL DEFAULT 1800/.test(mig),
  );
  push(
    "adds checkin_late_seconds default 5400",
    /checkin_late_seconds INT NOT NULL DEFAULT 5400/.test(mig),
  );
  push(
    "adds geofence_enabled BOOLEAN default FALSE",
    /geofence_enabled BOOLEAN NOT NULL DEFAULT FALSE/.test(mig),
  );

  push(
    "radius CHECK range [25, 5000]",
    /coaching_training_sessions_radius_range[\s\S]{0,300}location_radius_meters BETWEEN 25 AND 5000/.test(mig),
  );
  push(
    "checkin_early CHECK range [0, 86400]",
    /coaching_training_sessions_checkin_early_range[\s\S]{0,200}checkin_early_seconds BETWEEN 0 AND 86400/.test(mig),
  );
  push(
    "checkin_late CHECK range [0, 86400]",
    /coaching_training_sessions_checkin_late_range[\s\S]{0,200}checkin_late_seconds BETWEEN 0 AND 86400/.test(mig),
  );
  push(
    "geofence_requires_location CHECK",
    /geofence_requires_location[\s\S]{0,600}geofence_enabled = FALSE[\s\S]{0,200}location_lat IS NOT NULL[\s\S]{0,100}location_lng IS NOT NULL[\s\S]{0,100}location_radius_meters IS NOT NULL/.test(mig),
  );

  // Attendance columns + CHECKs.
  push(
    "adds checkin_lat / lng / accuracy_m columns",
    /ADD COLUMN IF NOT EXISTS checkin_lat DOUBLE PRECISION[\s\S]{0,200}checkin_lng DOUBLE PRECISION[\s\S]{0,200}checkin_accuracy_m INT/.test(mig),
  );
  push(
    "drops prior method CHECK before re-adding",
    /DO \$att\$[\s\S]{0,1000}DROP CONSTRAINT %I/.test(mig),
  );
  push(
    "re-adds method CHECK with auto_geo",
    /coaching_training_attendance_method_check[\s\S]{0,200}'qr', 'manual', 'auto_geo'/.test(mig),
  );
  push(
    "accuracy positive CHECK",
    /coaching_training_attendance_accuracy_positive[\s\S]{0,200}checkin_accuracy_m > 0/.test(mig),
  );
  push(
    "auto_geo requires coords CHECK",
    /auto_geo_has_coords[\s\S]{0,300}method <> 'auto_geo'[\s\S]{0,200}checkin_lat IS NOT NULL AND checkin_lng IS NOT NULL/.test(mig),
  );

  // Audit table.
  push(
    "creates coaching_attendance_audit",
    /CREATE TABLE IF NOT EXISTS public\.coaching_attendance_audit/.test(mig),
  );
  push(
    "audit outcome CHECK accepted|rejected",
    /coaching_attendance_audit_outcome_check[\s\S]{0,200}'accepted', 'rejected'/.test(mig),
  );
  push(
    "audit reason_code shape CHECK",
    /coaching_attendance_audit_reason_shape[\s\S]{0,300}reason_code IS NULL OR reason_code ~ '\^\[A-Z\]\[A-Z0-9_\]\{2,48\}\$'/.test(mig),
  );
  push(
    "audit session + athlete indexes",
    /coaching_attendance_audit_session_idx[\s\S]{0,200}\(session_id, checked_at DESC\)[\s\S]{0,400}coaching_attendance_audit_athlete_idx[\s\S]{0,200}\(athlete_user_id, checked_at DESC\)/.test(mig),
  );
  push(
    "audit RLS enabled",
    /ALTER TABLE public\.coaching_attendance_audit ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "audit self read policy",
    /coaching_attendance_audit_self_read[\s\S]{0,200}athlete_user_id = auth\.uid\(\)/.test(mig),
  );
  push(
    "audit staff read policy",
    /coaching_attendance_audit_staff_read[\s\S]{0,600}'admin_master', 'coach', 'assistant'/.test(mig),
  );
  push(
    "audit platform_admin read policy",
    /coaching_attendance_audit_platform_admin[\s\S]{0,400}platform_role = 'admin'/.test(mig),
  );

  // fn_session_checkin_window.
  push(
    "fn_session_checkin_window STABLE SECURITY INVOKER",
    /fn_session_checkin_window[\s\S]{0,400}STABLE[\s\S]{0,100}SECURITY INVOKER/.test(mig),
  );
  push(
    "window function derives is_open from status + now()",
    /fn_session_checkin_window[\s\S]{0,1200}status <> 'cancelled'[\s\S]{0,200}now\(\) >=[\s\S]{0,300}now\(\) <=/.test(mig),
  );
  push(
    "window function granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_session_checkin_window\(UUID\) TO authenticated/.test(mig),
  );

  // fn_auto_checkin.
  push(
    "fn_auto_checkin SECURITY DEFINER",
    /fn_auto_checkin[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "auto_checkin rejects unauthenticated",
    /fn_auto_checkin[\s\S]{0,600}v_uid IS NULL[\s\S]{0,200}'NOT_AUTHENTICATED'/.test(mig),
  );
  push(
    "auto_checkin validates lat/lng range",
    /p_lat < -90 OR p_lat > 90[\s\S]{0,200}p_lng < -180 OR p_lng > 180[\s\S]{0,400}'COORDS_INVALID'/.test(mig),
  );
  push(
    "auto_checkin rejects low GPS accuracy > 100m",
    /p_accuracy_m > 100[\s\S]{0,300}'GPS_ACCURACY_LOW'/.test(mig),
  );
  push(
    "auto_checkin rejects cancelled session",
    /status = 'cancelled'[\s\S]{0,400}'SESSION_CANCELLED'/.test(mig),
  );
  push(
    "auto_checkin requires geofence_enabled",
    /NOT v_session\.geofence_enabled[\s\S]{0,300}'GEOFENCE_DISABLED'/.test(mig),
  );
  push(
    "auto_checkin requires group membership",
    /NOT EXISTS[\s\S]{0,300}coaching_members[\s\S]{0,300}'NOT_IN_GROUP'/.test(mig),
  );
  push(
    "auto_checkin enforces check-in window",
    /now\(\) < v_window_open OR now\(\) > v_window_close[\s\S]{0,300}'WINDOW_CLOSED'/.test(mig),
  );
  push(
    "auto_checkin uses fn_haversine_m for distance",
    /public\.fn_haversine_m\([\s\S]{0,200}location_lat, v_session\.location_lng, p_lat, p_lng/.test(mig),
  );
  push(
    "auto_checkin rejects outside geofence",
    /v_distance_m > v_session\.location_radius_meters[\s\S]{0,400}'OUTSIDE_GEOFENCE'/.test(mig),
  );
  push(
    "auto_checkin idempotent via ON CONFLICT",
    /INSERT INTO public\.coaching_training_attendance[\s\S]{0,800}ON CONFLICT \(session_id, athlete_user_id\) DO NOTHING/.test(mig),
  );
  push(
    "auto_checkin writes method = 'auto_geo'",
    /VALUES[\s\S]{0,400}'auto_geo',[\s\S]{0,200}p_lat, p_lng, p_accuracy_m/.test(mig),
  );
  push(
    "auto_checkin audits rejected attempts",
    (mig.match(/fn_record_attendance_audit[\s\S]{0,200}'rejected'/g) || []).length >= 6,
  );
  push(
    "auto_checkin audits accepted outcome",
    /fn_record_attendance_audit[\s\S]{0,200}'accepted'/.test(mig),
  );
  push(
    "auto_checkin revokes from anon + PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_auto_checkin[\s\S]{0,200}FROM PUBLIC[\s\S]{0,400}FROM anon/.test(mig),
  );
  push(
    "auto_checkin granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_auto_checkin[\s\S]{0,200}TO authenticated/.test(mig),
  );

  // Audit writer.
  push(
    "fn_record_attendance_audit SECURITY DEFINER",
    /fn_record_attendance_audit[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "audit writer fail-open (RAISE WARNING)",
    /fn_record_attendance_audit[\s\S]{0,600}EXCEPTION WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING/.test(mig),
  );
  push(
    "audit writer revoked from PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_record_attendance_audit[\s\S]{0,200}FROM PUBLIC/.test(mig),
  );

  // Self-tests.
  push(
    "self-test asserts location_radius_meters column",
    /self-test: location_radius_meters column missing/.test(mig),
  );
  push(
    "self-test asserts geofence_enabled column",
    /self-test: geofence_enabled column missing/.test(mig),
  );
  push(
    "self-test asserts geofence_requires_location CHECK",
    /self-test: geofence_requires_location CHECK missing/.test(mig),
  );
  push(
    "self-test asserts radius_range CHECK",
    /self-test: radius_range CHECK missing/.test(mig),
  );
  push(
    "self-test asserts auto_geo_has_coords CHECK",
    /self-test: auto_geo_has_coords CHECK missing/.test(mig),
  );
  push(
    "self-test asserts method CHECK includes auto_geo",
    /self-test: method CHECK must include auto_geo/.test(mig),
  );
  push(
    "self-test asserts fn_auto_checkin presence",
    /self-test: fn_auto_checkin missing/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L23-08-presenca-em-treinos-coletivos-via-qr-code-staff.md",
);
const finding = safeRead(findingPath, "L23-08 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421660000_l23_08_geofenced_checkin\.sql/.test(finding),
  );
  push(
    "finding references fn_auto_checkin + geofence_enabled",
    /fn_auto_checkin/.test(finding) && /geofence_enabled/.test(finding),
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
  `\n${results.length - failed}/${results.length} geofenced-checkin checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-08 invariants broken.");
  process.exit(1);
}
