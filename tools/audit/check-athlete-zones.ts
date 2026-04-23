/**
 * check-athlete-zones.ts
 *
 * L21-05 — CI guard for the per-athlete pace/HR zone schema,
 * validators, anchor-derived preview, and classifier RPCs.
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

const migration = safeRead(
  resolve(ROOT, "supabase/migrations/20260421690000_l21_05_athlete_zones.sql"),
  "migration present",
);

if (migration) {
  push(
    "migration runs in a single transaction",
    /\bBEGIN;/.test(migration) && /\bCOMMIT;/.test(migration),
  );
  push(
    "fn_validate_pace_zones is IMMUTABLE + PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_pace_zones\(p_zones jsonb\)[\s\S]{0,200}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(migration),
  );
  push(
    "fn_validate_hr_zones is IMMUTABLE + PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_hr_zones\(p_zones jsonb\)[\s\S]{0,200}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(migration),
  );
  push(
    "pace validator enforces 3-7 zones",
    /v_count NOT BETWEEN 3 AND 7/.test(migration),
  );
  push(
    "pace validator enforces ascending bounds",
    /v_prev_max IS NOT NULL AND v_min < v_prev_max/.test(migration),
  );
  push(
    "pace validator enforces sec/km physiological range",
    /v_min NOT BETWEEN 120 AND 1200/.test(migration)
      && /v_max NOT BETWEEN 120 AND 1200/.test(migration),
  );
  push(
    "hr validator enforces bpm physiological range",
    /v_min NOT BETWEEN 40 AND 230/.test(migration)
      && /v_max NOT BETWEEN 40 AND 230/.test(migration),
  );
  push(
    "athlete_zones table exists with user_id as PK",
    /CREATE TABLE IF NOT EXISTS public\.athlete_zones[\s\S]{0,200}user_id\s+uuid PRIMARY KEY/.test(migration),
  );
  push(
    "athlete_zones carries pace_zones + hr_zones jsonb columns",
    /pace_zones\s+jsonb NOT NULL/.test(migration)
      && /hr_zones\s+jsonb NOT NULL/.test(migration),
  );
  push(
    "athlete_zones has version column defaulting to 1",
    /version\s+int NOT NULL DEFAULT 1/.test(migration),
  );
  push(
    "athlete_zones validates pace jsonb via CHECK → fn_validate_pace_zones",
    /CHECK \(public\.fn_validate_pace_zones\(pace_zones\)\)/.test(migration),
  );
  push(
    "athlete_zones validates hr jsonb via CHECK → fn_validate_hr_zones",
    /CHECK \(public\.fn_validate_hr_zones\(hr_zones\)\)/.test(migration),
  );
  push(
    "athlete_zones constrains updated_by to 3-value enum",
    /updated_by IN \('athlete_manual', 'auto_calculated', 'coach_assigned'\)/.test(migration),
  );
  push(
    "athlete_zones constrains LTHR range [80, 220]",
    /lthr_bpm BETWEEN 80 AND 220/.test(migration),
  );
  push(
    "athlete_zones constrains hr_max range [120, 230]",
    /hr_max_bpm BETWEEN 120 AND 230/.test(migration),
  );
  push(
    "athlete_zones constrains hr_rest range [30, 110]",
    /hr_rest_bpm BETWEEN 30 AND 110/.test(migration),
  );
  push(
    "athlete_zones enforces hr_rest < hr_max",
    /hr_rest_bpm < hr_max_bpm/.test(migration),
  );
  push(
    "athlete_zones enforces threshold_pace range [150, 900]",
    /threshold_pace_sec_km BETWEEN 150 AND 900/.test(migration),
  );
  push(
    "athlete_zones enforces vo2max range [15, 95]",
    /vo2max BETWEEN 15\.0 AND 95\.0/.test(migration),
  );
  push(
    "athlete_zones ENABLE ROW LEVEL SECURITY",
    /ALTER TABLE public\.athlete_zones ENABLE ROW LEVEL SECURITY/.test(migration),
  );
  push(
    "athlete_zones RLS: self read policy",
    /CREATE POLICY athlete_zones_self_read[\s\S]{0,300}user_id = auth\.uid\(\)/.test(migration),
  );
  push(
    "athlete_zones RLS: coach read policy scoped to shared group",
    /CREATE POLICY athlete_zones_coach_read[\s\S]{0,500}coaching_members[\s\S]{0,300}role IN \('admin_master', 'coach'\)/.test(migration),
  );
  push(
    "athlete_zone_history is append-only via trigger",
    /fn_athlete_zone_history_block_mutation[\s\S]{0,400}RAISE EXCEPTION 'athlete_zone_history is append-only'/.test(migration),
  );
  push(
    "athlete_zone_history trigger fires BEFORE UPDATE OR DELETE",
    /BEFORE UPDATE OR DELETE ON public\.athlete_zone_history/.test(migration),
  );
  push(
    "athlete_zone_history waives service_role",
    /current_setting\('role', true\) = 'service_role'[\s\S]{0,200}RETURN NEW/.test(migration),
  );
  push(
    "athlete_zone_history carries UNIQUE (user_id, version)",
    /UNIQUE \(user_id, version\)/.test(migration),
  );
  push(
    "snapshot trigger runs AFTER INSERT",
    /AFTER INSERT ON public\.athlete_zones[\s\S]{0,400}fn_athlete_zones_snapshot/.test(migration),
  );
  push(
    "snapshot trigger runs AFTER UPDATE guarded by WHEN",
    /AFTER UPDATE ON public\.athlete_zones[\s\S]{0,800}WHEN \([\s\S]{0,400}IS DISTINCT FROM/.test(migration),
  );
  push(
    "fn_athlete_zones_snapshot is SECURITY DEFINER",
    /fn_athlete_zones_snapshot[\s\S]{0,400}SECURITY DEFINER/.test(migration),
  );
  push(
    "fn_athlete_zones_snapshot execute revoked from PUBLIC",
    /REVOKE EXECUTE ON FUNCTION public\.fn_athlete_zones_snapshot\(\) FROM PUBLIC/.test(migration),
  );
  push(
    "fn_zones_compute_from_anchors is IMMUTABLE + PARALLEL SAFE",
    /fn_zones_compute_from_anchors\([\s\S]{0,200}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(migration),
  );
  push(
    "anchor compute rejects out-of-range LTHR",
    /p_lthr_bpm NOT BETWEEN 80 AND 220[\s\S]{0,200}RAISE EXCEPTION/.test(migration),
  );
  push(
    "anchor compute rejects out-of-range threshold pace",
    /p_threshold_pace_sec_km NOT BETWEEN 150 AND 900[\s\S]{0,200}RAISE EXCEPTION/.test(migration),
  );
  push(
    "anchor compute emits 5-zone pace array",
    /jsonb_build_array\([\s\S]{0,1500}'zone', 5,[\s\S]{0,400}'min_sec_km'/.test(migration),
  );
  push(
    "anchor compute emits 5-zone HR array",
    /jsonb_build_array\([\s\S]{0,1500}'zone', 5,[\s\S]{0,400}'min_bpm'/.test(migration),
  );
  push(
    "fn_zones_set is SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_zones_set\([\s\S]{0,1500}SECURITY DEFINER/.test(migration),
  );
  push(
    "fn_zones_set requires authentication",
    /fn_zones_set[\s\S]{0,1500}v_caller IS NULL[\s\S]{0,200}authentication required/.test(migration),
  );
  push(
    "fn_zones_set enforces caller = athlete OR group coach",
    /only the athlete or a group coach may set zones/.test(migration),
  );
  push(
    "fn_zones_set blocks coach from claiming athlete_manual",
    /coach cannot set updated_by=athlete_manual/.test(migration),
  );
  push(
    "fn_zones_set validates pace + hr payloads before upsert",
    /fn_validate_pace_zones\(p_pace_zones\)[\s\S]{0,400}fn_validate_hr_zones\(p_hr_zones\)/.test(migration),
  );
  push(
    "fn_zones_set uses SELECT ... FOR UPDATE to serialise version bump",
    /FROM public\.athlete_zones[\s\S]{0,200}FOR UPDATE/.test(migration),
  );
  push(
    "fn_zones_set upserts via ON CONFLICT (user_id)",
    /ON CONFLICT \(user_id\) DO UPDATE SET/.test(migration),
  );
  push(
    "fn_zones_set execute revoked from PUBLIC and granted to authenticated",
    /REVOKE EXECUTE ON FUNCTION public\.fn_zones_set[\s\S]{0,300}FROM PUBLIC/.test(migration)
      && /GRANT EXECUTE ON FUNCTION public\.fn_zones_set[\s\S]{0,300}TO authenticated/.test(migration),
  );
  push(
    "fn_zones_classify_pace is STABLE + SECURITY DEFINER",
    /fn_zones_classify_pace\(\s*p_user_id uuid,\s*p_pace_sec_km int\s*\)[\s\S]{0,200}STABLE[\s\S]{0,100}SECURITY DEFINER/.test(migration),
  );
  push(
    "fn_zones_classify_hr is STABLE + SECURITY DEFINER",
    /fn_zones_classify_hr\(\s*p_user_id uuid,\s*p_hr_bpm int\s*\)[\s\S]{0,200}STABLE[\s\S]{0,100}SECURITY DEFINER/.test(migration),
  );
  push(
    "classifiers enforce athlete-self or group-coach authorisation",
    /not authorised to classify this athlete/.test(migration),
  );
  push(
    "classifiers clamp below/above extreme zones instead of returning NULL",
    /RETURN \(v_zone ->> 'zone'\)::int/.test(migration),
  );
  push(
    "self-test: pace validator accepts canonical payload",
    /pace validator should have accepted/.test(migration),
  );
  push(
    "self-test: pace validator rejects zone=0 / short payloads",
    /pace validator should have rejected zone=0 or count=1/.test(migration),
  );
  push(
    "self-test: hr validator rejects overlapping zones",
    /hr validator should have rejected overlapping zones/.test(migration),
  );
  push(
    "self-test: anchor compute produces validator-accepted outputs",
    /computed pace zones failed validation/.test(migration)
      && /computed hr zones failed validation/.test(migration),
  );
  push(
    "self-test: pg_constraint presence asserted for all 4 shape checks",
    /athlete_zones_pace_zones_shape missing/.test(migration)
      && /athlete_zones_hr_zones_shape missing/.test(migration)
      && /athlete_zones_updated_by_enum missing/.test(migration)
      && /athlete_zone_history_unique_version missing/.test(migration),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L21-05-zonas-de-treino-pace-hr-nao-personalizaveis.md",
);
const finding = safeRead(findingPath, "L21-05 finding present");
if (finding) {
  push(
    "finding references migration",
    /supabase\/migrations\/20260421690000_l21_05_athlete_zones\.sql/.test(finding),
  );
  push(
    "finding references athlete_zones + fn_zones_compute_from_anchors",
    /athlete_zones/.test(finding)
      && (/fn_zones_compute_from_anchors/.test(finding)
          || /fn_zones_set/.test(finding)),
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
  `\n${results.length - failed}/${results.length} athlete-zones checks passed.`,
);
if (failed > 0) {
  console.error("\nL21-05 invariants broken.");
  process.exit(1);
}
