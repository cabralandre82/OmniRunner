/**
 * check-workout-messages.ts
 *
 * L23-03 — CI guard for the coach ↔ athlete inline messaging schema
 * attached to workout_delivery_items.
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
  resolve(ROOT, "supabase/migrations/20260421710000_l23_03_workout_messages.sql"),
  "migration present",
);

if (migration) {
  push(
    "migration runs in a single transaction",
    /\bBEGIN;/.test(migration) && /\bCOMMIT;/.test(migration),
  );
  push(
    "workout_messages table created",
    /CREATE TABLE IF NOT EXISTS public\.workout_messages/.test(migration),
  );
  push(
    "references workout_delivery_items with CASCADE",
    /workout_delivery_item_id[\s\S]{0,120}REFERENCES public\.workout_delivery_items\(id\) ON DELETE CASCADE/.test(
      migration,
    ),
  );
  push(
    "references coaching_groups",
    /group_id[\s\S]{0,120}REFERENCES public\.coaching_groups\(id\)/.test(migration),
  );
  push(
    "from_user_id and to_user_id reference auth.users",
    /from_user_id[\s\S]{0,60}REFERENCES auth\.users/.test(migration)
      && /to_user_id[\s\S]{0,60}REFERENCES auth\.users/.test(migration),
  );
  push(
    "CHECK: has text or audio payload",
    /CONSTRAINT chk_workout_messages_has_payload/.test(migration),
  );
  push(
    "CHECK: body_text length capped at 2000",
    /CONSTRAINT chk_workout_messages_text_len[\s\S]{0,200}<= 2000/.test(migration),
  );
  push(
    "CHECK: audio_url must be HTTPS + duration bounded 1-90s",
    /audio_url ~ \'\^https:\/\/\'[\s\S]{0,200}BETWEEN 1 AND 90/.test(migration),
  );
  push(
    "CHECK: sender cannot equal recipient",
    /CONSTRAINT chk_workout_messages_no_self_message/.test(migration)
      && /from_user_id <> to_user_id/.test(migration),
  );
  push(
    "RLS enabled on workout_messages",
    /ALTER TABLE public\.workout_messages ENABLE ROW LEVEL SECURITY/.test(migration),
  );
  push(
    "RLS: participant read policy exists",
    /CREATE POLICY workout_messages_participant_read/.test(migration),
  );
  push(
    "RLS: participant policy includes group staff via coaching_members",
    /coaching_members cm[\s\S]{0,200}cm\.role IN \('admin_master','coach','assistant'\)/.test(migration),
  );
  push(
    "RLS: direct INSERT blocked (WITH CHECK false)",
    /CREATE POLICY workout_messages_no_direct_write[\s\S]{0,200}WITH CHECK \(false\)/.test(migration),
  );
  push(
    "RLS: direct UPDATE blocked (USING false AND WITH CHECK false)",
    /CREATE POLICY workout_messages_no_direct_update[\s\S]{0,300}USING \(false\)[\s\S]{0,60}WITH CHECK \(false\)/.test(migration),
  );
  push(
    "RLS: direct DELETE blocked",
    /CREATE POLICY workout_messages_no_direct_delete[\s\S]{0,160}USING \(false\)/.test(migration),
  );
  push(
    "anon has no grants",
    !/GRANT[\s\S]{0,200}TO anon/.test(migration),
  );
  push(
    "authenticated gets SELECT only",
    /GRANT SELECT ON public\.workout_messages TO authenticated/.test(migration)
      && !/GRANT INSERT ON public\.workout_messages TO authenticated/.test(migration),
  );
  push(
    "service_role gets full DML",
    /GRANT SELECT, INSERT, UPDATE, DELETE ON public\.workout_messages TO service_role/.test(migration),
  );
  push(
    "read_at monotone guard trigger present",
    /CREATE OR REPLACE FUNCTION public\.fn_workout_messages_read_at_guard/.test(migration)
      && /trg_workout_messages_read_at_guard/.test(migration),
  );
  push(
    "read_at guard rejects changing body_text / audio_url",
    /only read_at can be updated on workout_messages/.test(migration),
  );
  push(
    "fn_workout_message_send is SECURITY DEFINER with search_path pinned",
    /CREATE OR REPLACE FUNCTION public\.fn_workout_message_send[\s\S]{0,600}SECURITY DEFINER[\s\S]{0,200}SET search_path = public, pg_temp/.test(migration),
  );
  push(
    "fn_workout_message_send resolves recipient from item.athlete_user_id / group coach",
    /v_to := v_item\.athlete_user_id/.test(migration)
      && /cm\.role = 'coach'/.test(migration),
  );
  push(
    "fn_workout_message_send rejects non-participant with P0004",
    /caller is not a participant of this thread[\s\S]{0,80}P0004/.test(migration),
  );
  push(
    "fn_workout_message_send rejects item not-found with P0002",
    /workout_delivery_item not found[\s\S]{0,80}P0002/.test(migration),
  );
  push(
    "fn_workout_message_send requires authentication with P0001",
    /authentication required[\s\S]{0,80}P0001/.test(migration),
  );
  push(
    "fn_workout_message_send rejects empty payload with P0005",
    /empty message[\s\S]{0,80}P0005/.test(migration),
  );
  push(
    "fn_workout_message_mark_read is SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_workout_message_mark_read[\s\S]{0,200}SECURITY DEFINER/.test(migration),
  );
  push(
    "fn_workout_message_mark_read restricts to recipient (P0004)",
    /only the recipient can mark a message as read[\s\S]{0,80}P0004/.test(migration),
  );
  push(
    "fn_workout_message_mark_read is idempotent (returns false if already)",
    /IF v_already IS NOT NULL THEN\s*RETURN false;/.test(migration),
  );
  push(
    "fn_workout_message_mark_read uses FOR UPDATE row lock",
    /FROM public\.workout_messages[\s\S]{0,120}FOR UPDATE/.test(migration),
  );
  push(
    "fn_workout_message_unread_count scoped to auth.uid()",
    /CREATE OR REPLACE FUNCTION public\.fn_workout_message_unread_count\(\)[\s\S]{0,400}to_user_id = auth\.uid\(\)/.test(migration),
  );
  push(
    "fn_workout_message_unread_count is STABLE",
    /fn_workout_message_unread_count\(\)[\s\S]{0,400}STABLE/.test(migration),
  );
  push(
    "send RPC revoked from PUBLIC + granted to authenticated + service_role",
    /REVOKE ALL ON FUNCTION public\.fn_workout_message_send[\s\S]{0,200}FROM PUBLIC/.test(migration)
      && /GRANT EXECUTE ON FUNCTION public\.fn_workout_message_send[\s\S]{0,200}TO authenticated/.test(migration)
      && /GRANT EXECUTE ON FUNCTION public\.fn_workout_message_send[\s\S]{0,200}TO service_role/.test(migration),
  );
  push(
    "mark_read RPC revoked + granted to authenticated",
    /REVOKE ALL ON FUNCTION public\.fn_workout_message_mark_read[\s\S]{0,200}FROM PUBLIC/.test(migration)
      && /GRANT EXECUTE ON FUNCTION public\.fn_workout_message_mark_read[\s\S]{0,200}TO authenticated/.test(migration),
  );
  push(
    "thread index on (workout_delivery_item_id, created_at)",
    /idx_workout_messages_thread[\s\S]{0,200}\(workout_delivery_item_id, created_at\)/.test(migration),
  );
  push(
    "partial index for unread recipient",
    /idx_workout_messages_recipient_unread[\s\S]{0,200}WHERE read_at IS NULL/.test(migration),
  );
  push(
    "group activity index on (group_id, created_at DESC)",
    /idx_workout_messages_group[\s\S]{0,200}\(group_id, created_at DESC\)/.test(migration),
  );
  push(
    "self-test block asserts table + CHECKs + RLS + RPCs",
    /L23-03 self-test: workout_messages table missing/.test(migration)
      && /L23-03 self-test: CHECK constraint/.test(migration)
      && /L23-03 self-test: RLS not enabled/.test(migration)
      && /L23-03 self-test: RPC[\s\S]{0,80}missing or not SECURITY DEFINER/.test(migration)
      && /L23-03 self-test: read_at guard trigger missing/.test(migration)
      && /L23-03 self-test: unread recipient partial index missing/.test(migration),
  );
  push(
    "self-test prints success notice",
    /L23-03 migration self-test passed/.test(migration),
  );
  push(
    "send RPC does not insert into any other table",
    !/INSERT INTO public\.(?!workout_messages\b)/m.test(migration.split("fn_workout_message_send")[1] ?? ""),
  );
  push(
    "send RPC never credits coin_ledger (OmniCoin policy)",
    !/coin_ledger/.test(migration),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L23-03-comunicacao-coach-atleta-carece.md",
);
const finding = safeRead(findingPath, "L23-03 finding present");
if (finding) {
  push(
    "finding references migration",
    /supabase\/migrations\/20260421710000_l23_03_workout_messages\.sql/.test(finding),
  );
  push(
    "finding references workout_messages + fn_workout_message_send",
    /workout_messages/.test(finding)
      && /fn_workout_message_send/.test(finding),
  );
  push(
    "finding references thread-append-only posture",
    /append-only|append only/i.test(finding),
  );
  push(
    "finding references audio shape (HTTPS + duration)",
    /https/i.test(finding) && /audio/i.test(finding),
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
  `\n${results.length - failed}/${results.length} workout-messages checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-03 invariants broken.");
  process.exit(1);
}
