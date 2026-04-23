/**
 * check-workout-template-library.ts
 *
 * L23-05 — CI guard for global workout template catalogue.
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
  "supabase/migrations/20260421650000_l23_05_workout_template_library.sql",
);
const mig = safeRead(migPath, "L23-05 migration present");

if (mig) {
  push(
    "creates workout_template_catalog",
    /CREATE TABLE IF NOT EXISTS public\.workout_template_catalog/.test(mig),
  );
  push(
    "slug UNIQUE",
    /slug\s+TEXT NOT NULL UNIQUE/.test(mig),
  );
  push(
    "slug shape CHECK",
    /workout_template_catalog_slug_shape[\s\S]{0,200}slug ~ '\^\[a-z\]\[a-z0-9_-\]\{2,62\}\$'/.test(mig),
  );
  push(
    "category CHECK enum (12 categories)",
    /workout_template_catalog_category_check[\s\S]{0,400}'base', 'tempo', 'threshold', 'interval'[\s\S]{0,200}'fartlek', 'hills'[\s\S]{0,200}'vo2max', 'strength', 'test'/.test(mig),
  );
  push(
    "workout_type CHECK enum",
    /workout_template_catalog_workout_type_check[\s\S]{0,400}'continuous', 'interval', 'regenerative', 'long_run'[\s\S]{0,200}'strength', 'technique', 'test', 'free', 'race', 'brick'/.test(mig),
  );
  push(
    "source CHECK enum (4 sources)",
    /workout_template_catalog_source_check[\s\S]{0,200}'daniels', 'pfitzinger', 'hudson', 'custom'/.test(mig),
  );
  push(
    "difficulty CHECK range [1,5]",
    /workout_template_catalog_difficulty_range[\s\S]{0,100}difficulty BETWEEN 1 AND 5/.test(mig),
  );
  push(
    "is_active flag defaults TRUE",
    /is_active\s+BOOLEAN NOT NULL DEFAULT TRUE/.test(mig),
  );
  push(
    "partial category index on is_active",
    /workout_template_catalog_category_idx[\s\S]{0,200}WHERE is_active/.test(mig),
  );
  push(
    "partial source index on is_active",
    /workout_template_catalog_source_idx[\s\S]{0,200}WHERE is_active/.test(mig),
  );

  push(
    "catalog RLS enabled",
    /ALTER TABLE public\.workout_template_catalog ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "catalog public read policy on is_active",
    /workout_template_catalog_public_read[\s\S]{0,200}is_active = TRUE/.test(mig),
  );
  push(
    "catalog platform_admin write policy",
    /workout_template_catalog_platform_admin[\s\S]{0,400}platform_role = 'admin'[\s\S]{0,400}WITH CHECK[\s\S]{0,200}platform_role = 'admin'/.test(mig),
  );

  push(
    "creates catalog blocks table",
    /CREATE TABLE IF NOT EXISTS public\.workout_template_catalog_blocks/.test(mig),
  );
  push(
    "blocks block_type CHECK enum",
    /workout_template_catalog_blocks_type_check[\s\S]{0,200}'warmup', 'interval', 'recovery', 'cooldown', 'steady'/.test(mig),
  );
  push(
    "blocks hr_zone CHECK range",
    /workout_template_catalog_blocks_hr_range[\s\S]{0,200}target_hr_zone BETWEEN 1 AND 5/.test(mig),
  );
  push(
    "blocks rpe_target CHECK range",
    /workout_template_catalog_blocks_rpe_range[\s\S]{0,200}rpe_target BETWEEN 1 AND 10/.test(mig),
  );
  push(
    "blocks has_prescription CHECK",
    /workout_template_catalog_blocks_has_prescription[\s\S]{0,200}duration_seconds IS NOT NULL OR distance_meters IS NOT NULL/.test(mig),
  );
  push(
    "blocks unique (catalog_id, order_index)",
    /workout_template_catalog_blocks_order_uniq[\s\S]{0,200}\(catalog_id, order_index\)/.test(mig),
  );
  push(
    "blocks RLS enabled",
    /ALTER TABLE public\.workout_template_catalog_blocks ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "blocks public read joins is_active",
    /workout_template_catalog_blocks_public_read[\s\S]{0,400}cat\.is_active = TRUE/.test(mig),
  );

  push(
    "seeds at least 12 canonical workouts",
    (mig.match(/INSERT INTO public\.workout_template_catalog\b/g) || []).length >= 1
      && (mig.match(/\('[a-z][a-z0-9_-]+',/g) || []).length >= 12,
  );
  push(
    "seeds include daniels source",
    /'daniels-tempo-20'[\s\S]{0,400}'daniels'/.test(mig),
  );
  push(
    "seeds include pfitzinger source",
    /'pfitzinger-long-24km-gmp'[\s\S]{0,400}'pfitzinger'/.test(mig),
  );
  push(
    "seeds include hudson source",
    /'hudson-fartlek-classic'[\s\S]{0,400}'hudson'/.test(mig),
  );
  push(
    "seeds include custom recovery + test",
    /'recovery-30-jog'[\s\S]{0,800}'test-5k-tt'/.test(mig),
  );
  push(
    "seeds ON CONFLICT DO NOTHING (idempotent)",
    /ON CONFLICT \(slug\) DO NOTHING/.test(mig),
  );
  push(
    "seeds 3 blocks for daniels-tempo-20",
    (mig.match(/WHERE cat\.slug = 'daniels-tempo-20'/g) || []).length >= 3,
  );

  push(
    "fn_clone_catalog_template SECURITY DEFINER",
    /fn_clone_catalog_template[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "clone rejects unauthenticated",
    /fn_clone_catalog_template[\s\S]{0,600}auth\.uid\(\) IS NULL/.test(mig),
  );
  push(
    "clone rejects inactive catalog",
    /is_active = TRUE[\s\S]{0,300}catalog template not found or inactive/.test(mig),
  );
  push(
    "clone enforces coach/admin_master role on target group",
    /only coach or admin_master of target group can clone/.test(mig),
  );
  push(
    "clone idempotent via catalog_slug anchor",
    /catalog_slug:' \|\| v_cat\.slug[\s\S]{0,400}IF v_existing_id IS NOT NULL THEN[\s\S]{0,80}RETURN v_existing_id/.test(mig),
  );
  push(
    "clone writes to coaching_workout_templates",
    /INSERT INTO public\.coaching_workout_templates/.test(mig),
  );
  push(
    "clone copies blocks ordered by order_index",
    /INSERT INTO public\.coaching_workout_blocks[\s\S]{0,600}ORDER BY b\.order_index/.test(mig),
  );
  push(
    "clone granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_clone_catalog_template[\s\S]{0,200}TO authenticated/.test(mig),
  );

  push(
    "fn_list_catalog_templates STABLE SECURITY INVOKER",
    /fn_list_catalog_templates[\s\S]{0,400}STABLE[\s\S]{0,100}SECURITY INVOKER/.test(mig),
  );
  push(
    "list filters is_active = TRUE",
    /fn_list_catalog_templates[\s\S]{0,1000}cat\.is_active = TRUE/.test(mig),
  );
  push(
    "list supports category + source + difficulty_max filters",
    /p_category IS NULL OR cat\.category = p_category[\s\S]{0,200}p_source IS NULL OR cat\.source = p_source[\s\S]{0,200}p_difficulty_max IS NULL OR cat\.difficulty <= p_difficulty_max/.test(mig),
  );
  push(
    "list granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_list_catalog_templates[\s\S]{0,200}TO authenticated/.test(mig),
  );

  push(
    "self-test: 12+ seeds",
    /self-test: expected at least 12 catalogue seeds/.test(mig),
  );
  push(
    "self-test: 4 sources represented",
    /self-test: expected all 4 sources represented/.test(mig),
  );
  push(
    "self-test: daniels-tempo-20 has 3 blocks",
    /self-test: daniels-tempo-20 must have 3 blocks/.test(mig),
  );
  push(
    "self-test asserts slug shape CHECK presence",
    /self-test: catalog slug shape CHECK missing/.test(mig),
  );
  push(
    "self-test asserts blocks order unique index presence",
    /self-test: catalogue blocks order unique index missing/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L23-05-workout-template-library-pobre.md",
);
const finding = safeRead(findingPath, "L23-05 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421650000_l23_05_workout_template_library\.sql/.test(finding),
  );
  push(
    "finding references workout_template_catalog + fn_clone_catalog_template",
    /workout_template_catalog/.test(finding)
      && /fn_clone_catalog_template/.test(finding),
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
  `\n${results.length - failed}/${results.length} workout-template-library checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-05 invariants broken.");
  process.exit(1);
}
