/**
 * check-paired-workouts.ts
 *
 * L23-10 — CI guard for paired / grouped workout primitives.
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
  "supabase/migrations/20260421680000_l23_10_paired_workouts.sql",
);
const mig = safeRead(migPath, "L23-10 migration present");

if (mig) {
  // Pairings table.
  push(
    "creates coaching_workout_pairings table",
    /CREATE TABLE IF NOT EXISTS public\.coaching_workout_pairings/.test(mig),
  );
  push(
    "pairings status CHECK enum with 5 states",
    /coaching_workout_pairings_status_check[\s\S]{0,400}'pending', 'all_confirmed', 'partially_confirmed',[\s\S]{0,100}'dissolved', 'completed'/.test(mig),
  );
  push(
    "pairings min_confirmations CHECK [2, 20]",
    /coaching_workout_pairings_min_confirmations_range[\s\S]{0,200}min_confirmations BETWEEN 2 AND 20/.test(mig),
  );
  push(
    "pairings title length CHECK",
    /coaching_workout_pairings_title_length[\s\S]{0,200}length\(trim\(title\)\) BETWEEN 2 AND 120/.test(mig),
  );
  push(
    "pairings dissolved_timestamp biconditional CHECK",
    /coaching_workout_pairings_dissolved_timestamp[\s\S]{0,200}\(status = 'dissolved'\) = \(dissolved_at IS NOT NULL\)/.test(mig),
  );
  push(
    "pairings completed_timestamp biconditional CHECK",
    /coaching_workout_pairings_completed_timestamp[\s\S]{0,200}\(status = 'completed'\) = \(completed_at IS NOT NULL\)/.test(mig),
  );
  push(
    "pairings group+date index",
    /coaching_workout_pairings_group_date_idx[\s\S]{0,200}\(group_id, scheduled_date DESC\)/.test(mig),
  );
  push(
    "pairings partial active status index",
    /coaching_workout_pairings_group_status_idx[\s\S]{0,200}WHERE status IN \('pending', 'partially_confirmed'\)/.test(mig),
  );
  push(
    "pairings RLS enabled",
    /ALTER TABLE public\.coaching_workout_pairings ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "pairings group_read policy",
    /coaching_workout_pairings_group_read[\s\S]{0,400}EXISTS[\s\S]{0,200}coaching_members/.test(mig),
  );
  push(
    "pairings staff_write policy",
    /coaching_workout_pairings_staff_write[\s\S]{0,500}'admin_master', 'coach'/.test(mig),
  );

  // Members table.
  push(
    "creates coaching_workout_pairing_members table",
    /CREATE TABLE IF NOT EXISTS public\.coaching_workout_pairing_members/.test(mig),
  );
  push(
    "member confirmation_status CHECK enum",
    /coaching_workout_pairing_members_confirmation_check[\s\S]{0,200}'pending', 'confirmed', 'declined'/.test(mig),
  );
  push(
    "member responded_timestamp CHECK",
    /coaching_workout_pairing_members_responded_timestamp[\s\S]{0,600}confirmation_status = 'pending' AND responded_at IS NULL[\s\S]{0,300}IN \('confirmed', 'declined'\)[\s\S]{0,200}responded_at IS NOT NULL/.test(mig),
  );
  push(
    "member decline_reason shape CHECK",
    /coaching_workout_pairing_members_decline_has_reason_shape[\s\S]{0,400}confirmation_status = 'declined'[\s\S]{0,200}length\(trim\(decline_reason\)\) BETWEEN 1 AND 280/.test(mig),
  );
  push(
    "member unique assignment_id (one pairing per assignment)",
    /coaching_workout_pairing_members_assignment_uniq[\s\S]{0,200}\(assignment_id\)/.test(mig),
  );
  push(
    "member unique (pairing_id, athlete_user_id)",
    /coaching_workout_pairing_members_pairing_athlete_uniq[\s\S]{0,200}\(pairing_id, athlete_user_id\)/.test(mig),
  );
  push(
    "member athlete index",
    /coaching_workout_pairing_members_athlete_idx[\s\S]{0,200}\(athlete_user_id, confirmation_status\)/.test(mig),
  );
  push(
    "member RLS enabled",
    /ALTER TABLE public\.coaching_workout_pairing_members ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "member group_read policy",
    /coaching_workout_pairing_members_group_read/.test(mig),
  );

  // fn_pairing_recompute_status.
  push(
    "fn_pairing_recompute_status SECURITY DEFINER",
    /fn_pairing_recompute_status[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "recompute: completed takes precedence",
    /BOOL_AND\(a\.status = 'completed'\)/.test(mig)
      && /IF v_completed THEN[\s\S]{0,200}'completed'/.test(mig),
  );
  push(
    "recompute: dissolved when unable to reach min",
    /v_total - v_declined < v_min_conf[\s\S]{0,200}'dissolved'/.test(mig),
  );
  push(
    "recompute: all_confirmed when v_confirmed = v_total",
    /v_confirmed = v_total[\s\S]{0,200}'all_confirmed'/.test(mig),
  );
  push(
    "recompute: partially_confirmed when v_confirmed > 0",
    /v_confirmed > 0[\s\S]{0,200}'partially_confirmed'/.test(mig),
  );
  push(
    "recompute: revokes from PUBLIC",
    /REVOKE ALL ON FUNCTION public\.fn_pairing_recompute_status\(UUID\) FROM PUBLIC/.test(mig),
  );

  // fn_pairing_create.
  push(
    "fn_pairing_create SECURITY DEFINER",
    /fn_pairing_create[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "create: only admin_master or coach",
    /only admin_master or coach can create pairing/.test(mig),
  );
  push(
    "create: requires at least 2 assignments",
    /pairing requires at least two assignments/.test(mig),
  );
  push(
    "create: enforces 20-member ceiling",
    /pairing cannot exceed 20 members/.test(mig),
  );
  push(
    "create: all assignments must share group + date",
    /all assignments must share group \+ scheduled_date/.test(mig),
  );
  push(
    "create: refuses assignments already paired",
    /one or more assignments already belong to a pairing/.test(mig),
  );
  push(
    "create: calls fn_pairing_recompute_status",
    /INSERT INTO public\.coaching_workout_pairing_members[\s\S]{0,800}PERFORM public\.fn_pairing_recompute_status/.test(mig),
  );
  push(
    "create granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_pairing_create[\s\S]{0,200}TO authenticated/.test(mig),
  );

  // fn_pairing_respond.
  push(
    "fn_pairing_respond SECURITY DEFINER",
    /fn_pairing_respond[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "respond: confirmed|declined only",
    /confirmation must be confirmed or declined/.test(mig),
  );
  push(
    "respond: decline requires reason",
    /decline requires a reason/.test(mig),
  );
  push(
    "respond: caller must be member",
    /not a member of this pairing/.test(mig),
  );
  push(
    "respond: refuses terminal pairing (P0005)",
    /pairing already terminal \(%\)[\s\S]{0,200}P0005/.test(mig),
  );
  push(
    "respond: FOR UPDATE to serialize write",
    /fn_pairing_respond[\s\S]{0,1500}FOR UPDATE/.test(mig),
  );
  push(
    "respond: recomputes aggregate status",
    /fn_pairing_respond[\s\S]{0,2500}PERFORM public\.fn_pairing_recompute_status/.test(mig)
      || /fn_pairing_respond[\s\S]{0,2500}fn_pairing_recompute_status\(p_pairing_id\)/.test(mig),
  );
  push(
    "respond: emits outbox event on decline",
    /workout\.pairing\.partner_declined/.test(mig),
  );
  push(
    "respond: outbox emission is fail-open",
    /workout\.pairing\.partner_declined[\s\S]{0,1500}EXCEPTION WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING 'outbox emit failed/.test(mig),
  );
  push(
    "respond: guarded by to_regproc on outbox emitter",
    /fn_pairing_respond[\s\S]{0,2500}to_regproc\('public\.fn_outbox_emit/.test(mig),
  );
  push(
    "respond granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_pairing_respond[\s\S]{0,200}TO authenticated/.test(mig),
  );

  // Self-tests.
  push(
    "self-test asserts pairings status_check",
    /self-test: pairings status_check missing/.test(mig),
  );
  push(
    "self-test asserts dissolved_timestamp CHECK",
    /self-test: dissolved_timestamp CHECK missing/.test(mig),
  );
  push(
    "self-test asserts responded_timestamp CHECK",
    /self-test: responded_timestamp CHECK missing/.test(mig),
  );
  push(
    "self-test asserts assignment uniq index",
    /self-test: assignment uniq index missing/.test(mig),
  );

  push(
    "migration runs in single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L23-10-treinos-com-dependencia-entre-atletas-par-grupo.md",
);
const finding = safeRead(findingPath, "L23-10 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421680000_l23_10_paired_workouts\.sql/.test(finding),
  );
  push(
    "finding references pairing primitives",
    /coaching_workout_pairings/.test(finding)
      && /fn_pairing_respond/.test(finding),
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
  `\n${results.length - failed}/${results.length} paired-workouts checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-10 invariants broken.");
  process.exit(1);
}
