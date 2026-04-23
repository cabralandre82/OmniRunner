/**
 * check-staff-team-dashboard.ts
 *
 * L21-12 — CI guard for staff team dashboard primitives.
 *
 * Invariants:
 *   1. `coaching_members.role` CHECK constraint drop-and-re-added with
 *      the expanded set {admin_master, coach, assistant, physio,
 *      nutritionist, psychologist, athlete}.
 *   2. `fn_is_staff_role(text)` IMMUTABLE PARALLEL SAFE; returns
 *      FALSE for `athlete` and NULL.
 *   3. `public.role_permissions` table with composite PK,
 *      role CHECK enum, permission shape CHECK (`namespace.action`).
 *   4. role_permissions RLS: public read, platform_admin write.
 *   5. Seed includes the canonical matrix for all six + athlete.
 *      Seed uses ON CONFLICT DO NOTHING (idempotent).
 *   6. `fn_role_has_permission(text, text)` STABLE PARALLEL SAFE;
 *      NULL-safe (returns FALSE for NULL inputs).
 *   7. `public.athlete_staff_access` — composite PK, permission
 *      shape CHECK, timestamp ordering CHECK, partial staff index
 *      on `revoked_at IS NULL`. RLS: athlete-own write, staff read
 *      of own rows, platform_admin read.
 *   8. `fn_my_role_in_group_ext(uuid)` STABLE SECURITY DEFINER.
 *      Returns `{role, is_staff, permissions}` jsonb. NULL role
 *      yields empty permissions.
 *   9. Self-test covers 5 permission-matrix cases + staff helper
 *      cases + CHECK presence.
 *  10. Migration runs in a single transaction.
 *
 * Usage: npm run audit:staff-team-dashboard
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
  "supabase/migrations/20260421630000_l21_12_staff_team_dashboard.sql",
);
const mig = safeRead(migPath, "L21-12 migration file present");

if (mig) {
  // coaching_members.role CHECK.
  push(
    "drops prior coaching_members.role CHECK",
    /DO \$cm_role\$[\s\S]{0,800}ALTER TABLE public\.coaching_members DROP CONSTRAINT/.test(mig),
  );
  push(
    "adds expanded coaching_members_role_check with 7 roles",
    /CONSTRAINT coaching_members_role_check CHECK \([\s\S]{0,200}'admin_master','coach','assistant','physio','nutritionist','psychologist','athlete'/.test(mig),
  );

  // Helpers.
  push(
    "defines fn_is_staff_role IMMUTABLE PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_is_staff_role[\s\S]{0,400}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(mig),
  );
  push(
    "fn_is_staff_role excludes athlete",
    /fn_is_staff_role[\s\S]{0,400}'admin_master','coach','assistant','physio','nutritionist','psychologist'/.test(mig)
      && !/fn_is_staff_role[\s\S]{0,200}p_role IN [^)]*'athlete'/.test(mig),
  );
  push(
    "grants fn_is_staff_role to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_is_staff_role\(TEXT\) TO PUBLIC/.test(mig),
  );

  // role_permissions table.
  push(
    "creates role_permissions table",
    /CREATE TABLE IF NOT EXISTS public\.role_permissions/.test(mig),
  );
  push(
    "role_permissions composite PK",
    /PRIMARY KEY \(role, permission\)/.test(mig),
  );
  push(
    "role_permissions role CHECK enum",
    /CONSTRAINT role_permissions_role_check[\s\S]{0,200}'admin_master','coach','assistant','physio','nutritionist','psychologist','athlete'/.test(mig),
  );
  push(
    "role_permissions permission shape CHECK",
    /CONSTRAINT role_permissions_permission_shape CHECK \(\s*permission ~ '\^\[a-z\]\[a-z0-9_\]\*\\\.\[a-z\]\[a-z0-9_\]\*\$'\s*\)/.test(mig),
  );
  push(
    "role_permissions RLS enabled",
    /ALTER TABLE public\.role_permissions ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "role_permissions public read policy",
    /role_permissions_public_read[\s\S]{0,100}FOR SELECT USING \(TRUE\)/.test(mig),
  );
  push(
    "role_permissions platform_admin write policy",
    /role_permissions_platform_admin_write[\s\S]{0,400}platform_role = 'admin'[\s\S]{0,400}WITH CHECK[\s\S]{0,200}platform_role = 'admin'/.test(mig),
  );

  // Seed.
  push(
    "seeds coach has athlete.health.read",
    /\('coach', 'athlete\.health\.read', TRUE\)/.test(mig),
  );
  push(
    "seeds physio has athlete.health.notes.write",
    /\('physio', 'athlete\.health\.notes\.write', TRUE\)/.test(mig),
  );
  push(
    "seeds nutritionist has athlete.nutrition.write",
    /\('nutritionist', 'athlete\.nutrition\.write', TRUE\)/.test(mig),
  );
  push(
    "seeds psychologist has athlete.mental.write",
    /\('psychologist', 'athlete\.mental\.write', TRUE\)/.test(mig),
  );
  push(
    "seeds athlete has training_plan.read",
    /\('athlete', 'training_plan\.read', TRUE\)/.test(mig),
  );
  push(
    "seeds admin_master has group.branding.manage",
    /\('admin_master', 'group\.branding\.manage', TRUE\)/.test(mig),
  );
  push(
    "seed uses ON CONFLICT DO NOTHING",
    /ON CONFLICT \(role, permission\) DO NOTHING/.test(mig),
  );

  // fn_role_has_permission.
  push(
    "defines fn_role_has_permission STABLE PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_role_has_permission[\s\S]{0,400}STABLE[\s\S]{0,120}PARALLEL SAFE/.test(mig),
  );
  push(
    "fn_role_has_permission NULL-safe",
    /fn_role_has_permission[\s\S]{0,600}p_role IS NULL OR p_permission IS NULL THEN[\s\S]{0,80}RETURN FALSE/.test(mig),
  );
  push(
    "fn_role_has_permission uses COALESCE false",
    /RETURN COALESCE\(v_granted, FALSE\)/.test(mig),
  );
  push(
    "grants fn_role_has_permission to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_role_has_permission\(TEXT, TEXT\) TO PUBLIC/.test(mig),
  );

  // athlete_staff_access.
  push(
    "creates athlete_staff_access table",
    /CREATE TABLE IF NOT EXISTS public\.athlete_staff_access/.test(mig),
  );
  push(
    "athlete_staff_access composite PK",
    /PRIMARY KEY \(athlete_id, staff_id, permission\)/.test(mig),
  );
  push(
    "athlete_staff_access permission shape CHECK",
    /CONSTRAINT athlete_staff_access_permission_shape CHECK \(\s*permission ~/.test(mig),
  );
  push(
    "athlete_staff_access timestamp ordering CHECK",
    /CONSTRAINT athlete_staff_access_timestamp_order CHECK \(\s*revoked_at IS NULL OR revoked_at >= granted_at\s*\)/.test(mig),
  );
  push(
    "athlete_staff_access partial staff index",
    /CREATE INDEX IF NOT EXISTS athlete_staff_access_staff_idx[\s\S]{0,200}WHERE revoked_at IS NULL/.test(mig),
  );
  push(
    "athlete_staff_access RLS enabled",
    /ALTER TABLE public\.athlete_staff_access ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "athlete_staff_access athlete-own write policy",
    /athlete_staff_access_own[\s\S]{0,200}FOR ALL USING \(athlete_id = auth\.uid\(\)\)[\s\S]{0,100}WITH CHECK \(athlete_id = auth\.uid\(\)\)/.test(mig),
  );
  push(
    "athlete_staff_access staff-read policy",
    /athlete_staff_access_staff_read[\s\S]{0,200}staff_id = auth\.uid\(\)/.test(mig),
  );
  push(
    "athlete_staff_access platform_admin policy",
    /athlete_staff_access_platform_admin[\s\S]{0,200}platform_role = 'admin'/.test(mig),
  );

  // fn_my_role_in_group_ext.
  push(
    "defines fn_my_role_in_group_ext STABLE SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_my_role_in_group_ext[\s\S]{0,400}STABLE[\s\S]{0,120}SECURITY DEFINER/.test(mig),
  );
  push(
    "ext returns role + is_staff + permissions",
    /jsonb_build_object\(\s*'role', v_role,\s*'is_staff', public\.fn_is_staff_role\(v_role\),\s*'permissions', to_jsonb\(v_permissions\)\s*\)/.test(mig),
  );
  push(
    "ext empty permissions on NULL role",
    /IF v_role IS NULL THEN[\s\S]{0,200}'permissions', '\[\]'::jsonb/.test(mig),
  );
  push(
    "ext grants to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_my_role_in_group_ext\(UUID\) TO authenticated, service_role/.test(mig),
  );

  // Self-test.
  push(
    "self-test: fn_is_staff_role rejects athlete",
    /self-test: fn_is_staff_role accepted athlete/.test(mig),
  );
  push(
    "self-test: coach has athlete.health.read",
    /self-test: coach must have athlete\.health\.read/.test(mig),
  );
  push(
    "self-test: nutritionist blocked from mental.write",
    /self-test: nutritionist must NOT have athlete\.mental\.write/.test(mig),
  );
  push(
    "self-test: physio blocked from nutrition.write",
    /self-test: physio must NOT have athlete\.nutrition\.write/.test(mig),
  );
  push(
    "self-test: psychologist has mental.write",
    /self-test: psychologist must have athlete\.mental\.write/.test(mig),
  );
  push(
    "self-test: athlete blocked from training_plan.manage",
    /self-test: athlete must NOT have training_plan\.manage/.test(mig),
  );
  push(
    "self-test asserts coaching_members_role_check presence",
    /self-test: coaching_members_role_check missing after expansion/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L21-12-sem-team-dashboard-para-staff-tecnica.md",
);
const finding = safeRead(findingPath, "L21-12 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421630000_l21_12_staff_team_dashboard\.sql/.test(finding),
  );
  push(
    "finding references role_permissions + fn_my_role_in_group_ext",
    /role_permissions[\s\S]{0,400}fn_my_role_in_group_ext/.test(finding),
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
  `\n${results.length - failed}/${results.length} staff-team-dashboard checks passed.`,
);
if (failed > 0) {
  console.error("\nL21-12 invariants broken.");
  process.exit(1);
}
