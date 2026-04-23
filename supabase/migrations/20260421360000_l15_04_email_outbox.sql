-- ============================================================================
-- L15-04 — Transactional email outbox + idempotent enqueue/dispatch primitives
--
-- Audit reference:
--   docs/audit/findings/L15-04-sem-email-transactional-platform.md
--   docs/audit/parts/06-middleware-contracts-cmo-cao.md  (anchor [15.4])
--
-- Problem
-- ───────
--   The CMO audit flagged that:
--
--     grep 'resend|postmark|sendgrid|mailgun' portal/src supabase/functions
--     → 0 matches.
--
--   The only email path we had was the Supabase Auth built-in SMTP — which
--   is unconfigured in this project (no `[auth.email.smtp]` block) and ships
--   with the default hosted Supabase outbound quota (2 emails/hour/user per
--   `auth.rate_limit.email_sent = 2`). Every "your withdraw was processed",
--   "receipt for purchase", "coaching invite" email that product copy
--   implied we sent was NOT being sent. Worse, had we turned on `enable_
--   confirmations = true` on signup (which we want for L10-09 anti-
--   credential-stuffing), we would have saturated the quota in minutes.
--
--   No outbox, no idempotency, no retry, no template registry, no provider
--   abstraction, no per-user delivery audit.
--
-- Defence (this migration — the DB-foundation piece)
-- ───────
--   Six DB objects + one self-test. The Edge Function + shared module +
--   template registry + runbook land in the same PR but outside SQL.
--
--     1. **`public.email_outbox`** — canonical queue of every transactional
--        email. Every enqueue lands a row. Every dispatch attempt mutates
--        `attempts` + `last_error`. Every success flips `status='sent'` +
--        sets `provider` + `provider_message_id` + `sent_at`. Every
--        terminal failure flips `status='failed'` + `failed_at`.
--
--        Columns:
--          id                   uuid   pk (generated)
--          recipient_email      text   not null (normalised lower + trim)
--          recipient_user_id    uuid?  — nullable for onboarding/unknown-
--                                        user flows (welcome, forgot-pwd)
--          template_key         text   not null — key into the template
--                                                  registry (manifest.json)
--          subject              text   not null — snapshot of the subject
--                                                  at enqueue time so
--                                                  moderators/support see
--                                                  what was actually sent
--          template_vars        jsonb  not null default '{}' — variables
--                                                            interpolated
--          idempotency_key      text   not null unique — dedup fence; same
--                                                       key within retention
--                                                       returns the same row
--          status               text   not null check in (
--                                        'pending','sending','sent','failed','suppressed'
--                                      ) default 'pending'
--          provider             text?  — e.g. 'resend', 'inbucket', 'null'
--          provider_message_id  text?  — opaque id returned by the provider
--          attempts             int    not null default 0 check >= 0
--          last_error           text?  — last provider error (trimmed)
--          created_at           timestamptz not null default now()
--          updated_at           timestamptz not null default now()
--          sent_at              timestamptz?
--          failed_at            timestamptz?
--
--        `idempotency_key` is UNIQUE — enqueuing the same key twice returns
--        the same row (handled by `fn_enqueue_email` below). This is the
--        per-email idempotency fence (L18-04 `idempotency_keys` generic
--        table handles cross-request financial idempotency; this table
--        owns email-specific dedup since emails are queued from many
--        different backend paths that don't always have access to the
--        generic fence).
--
--     2. **`public.fn_enqueue_email(recipient_email, recipient_user_id,
--                                   template_key, subject, template_vars,
--                                   idempotency_key)`**
--        SECURITY DEFINER, `search_path=public,pg_temp`. Normalises
--        `recipient_email` (lower + trim), validates the required fields,
--        INSERTs with `ON CONFLICT (idempotency_key) DO NOTHING`, then
--        SELECTs the row (existing or newly-inserted) and returns its id.
--        Never raises 23505 — callers can safely call this with a
--        deterministic key (e.g. a `withdrawal_id`) in a retry loop
--        without any conflict handling.
--
--     3. **`public.fn_mark_email_sent(id, provider, provider_message_id)`**
--        SECURITY DEFINER. Idempotent terminal transition:
--          status pending/sending  → sent (+provider/provider_message_id/sent_at)
--          status sent             → no-op (returns TRUE — already done)
--          status failed/suppressed → raises (terminal-state transition
--                                            violates the envelope)
--        Returns TRUE if the row transitioned OR was already `sent`.
--
--     4. **`public.fn_mark_email_failed(id, error, terminal)`**
--        SECURITY DEFINER. Idempotent failure transition:
--          status pending/sending  → if terminal → failed (+failed_at)
--                                    else        → pending (attempts++)
--          status failed           → no-op (returns TRUE)
--          status sent/suppressed  → raises
--
--     5. **`public.fn_email_outbox_assert_shape()`**
--        SECURITY DEFINER. Validates table + all CHECK constraints + RLS
--        forced + the three helper functions exist + only service_role has
--        EXECUTE on the mutating helpers + the UNIQUE index on
--        idempotency_key exists. Raises P0010 with the missing list.
--
--     6. **Self-test DO-block** at the end — exercises enqueue twice with
--        same key (dedup), mark sent, idempotent re-mark, mark failed,
--        transition guards.
--
-- RLS / privileges
-- ────────────────
--   ENABLE + FORCE ROW LEVEL SECURITY. One policy `email_outbox_service`
--   FOR ALL to `service_role` with `USING (true) WITH CHECK (true)`.
--   Users CANNOT read their email history directly — support surfaces that
--   through portal-admin routes if ever needed (scope out here).
--   Functions: REVOKE ALL FROM PUBLIC/anon/authenticated. GRANT EXECUTE
--   to service_role only.
--
-- Retention
-- ─────────
--   Out-of-scope for this migration. A pg_cron job (`email-outbox-gc`) is
--   documented in the runbook §4.5 to prune rows older than 90 days where
--   `status IN ('sent','failed','suppressed')`. The runbook ships as a
--   follow-up recipe so ops can tune retention per regulatory needs
--   (LGPD: 5-year minimum for financial receipts = keep a separate
--   projection table; L15-04 outbox is operational not regulatory).
--
-- Verification
-- ────────────
--   • Self-test DO-block at the bottom.
--   • Integration tests in tools/test_l15_04_email_outbox.ts (docker exec
--     psql, 15 cases).
--   • CI guard: npm run audit:email-platform.
-- ============================================================================

BEGIN;

-- 1. email_outbox table -------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.email_outbox (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_email      text NOT NULL,
  recipient_user_id    uuid NULL,
  template_key         text NOT NULL,
  subject              text NOT NULL,
  template_vars        jsonb NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key      text NOT NULL,
  status               text NOT NULL DEFAULT 'pending',
  provider             text NULL,
  provider_message_id  text NULL,
  attempts             integer NOT NULL DEFAULT 0,
  last_error           text NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  sent_at              timestamptz NULL,
  failed_at            timestamptz NULL
);

-- Defensive ADD CONSTRAINT blocks make the migration re-runnable on envs
-- where the table was created without these constraints (shouldn't happen
-- in-tree but future re-orgs are easier this way).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.email_outbox'::regclass
       AND conname  = 'email_outbox_status_check'
  ) THEN
    ALTER TABLE public.email_outbox
      ADD CONSTRAINT email_outbox_status_check
      CHECK (status IN ('pending','sending','sent','failed','suppressed'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.email_outbox'::regclass
       AND conname  = 'email_outbox_recipient_email_check'
  ) THEN
    ALTER TABLE public.email_outbox
      ADD CONSTRAINT email_outbox_recipient_email_check
      CHECK (recipient_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.email_outbox'::regclass
       AND conname  = 'email_outbox_template_key_check'
  ) THEN
    ALTER TABLE public.email_outbox
      ADD CONSTRAINT email_outbox_template_key_check
      CHECK (template_key ~ '^[a-z][a-z0-9_]{2,63}$');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.email_outbox'::regclass
       AND conname  = 'email_outbox_idempotency_key_check'
  ) THEN
    ALTER TABLE public.email_outbox
      ADD CONSTRAINT email_outbox_idempotency_key_check
      CHECK (length(idempotency_key) BETWEEN 8 AND 256);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.email_outbox'::regclass
       AND conname  = 'email_outbox_attempts_check'
  ) THEN
    ALTER TABLE public.email_outbox
      ADD CONSTRAINT email_outbox_attempts_check
      CHECK (attempts >= 0);
  END IF;
END$$;

CREATE UNIQUE INDEX IF NOT EXISTS email_outbox_idempotency_key_uniq
  ON public.email_outbox (idempotency_key);

CREATE INDEX IF NOT EXISTS email_outbox_status_created_at_idx
  ON public.email_outbox (status, created_at DESC);

CREATE INDEX IF NOT EXISTS email_outbox_recipient_user_idx
  ON public.email_outbox (recipient_user_id, created_at DESC)
  WHERE recipient_user_id IS NOT NULL;

COMMENT ON TABLE public.email_outbox IS
  'L15-04: canonical queue for every transactional email. Each row = one '
  'delivery attempt lifecycle keyed by a deterministic idempotency_key. '
  'Service-role only. Mutate via fn_enqueue_email / fn_mark_email_sent / '
  'fn_mark_email_failed — never direct UPDATE.';

ALTER TABLE public.email_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_outbox FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_outbox_service ON public.email_outbox;
CREATE POLICY email_outbox_service
  ON public.email_outbox
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- 2. fn_enqueue_email ---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_enqueue_email(
  p_recipient_email   text,
  p_recipient_user_id uuid,
  p_template_key      text,
  p_subject           text,
  p_template_vars     jsonb,
  p_idempotency_key   text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email_normalised text;
  v_subject          text;
  v_vars             jsonb;
  v_id               uuid;
BEGIN
  IF p_recipient_email IS NULL OR length(trim(p_recipient_email)) = 0 THEN
    RAISE EXCEPTION 'INVALID_RECIPIENT: p_recipient_email is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_template_key IS NULL OR length(trim(p_template_key)) = 0 THEN
    RAISE EXCEPTION 'INVALID_TEMPLATE_KEY: p_template_key is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_subject IS NULL OR length(trim(p_subject)) = 0 THEN
    RAISE EXCEPTION 'INVALID_SUBJECT: p_subject is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'INVALID_IDEMPOTENCY_KEY: p_idempotency_key must be >= 8 chars'
      USING ERRCODE = '22023';
  END IF;

  v_email_normalised := lower(trim(p_recipient_email));
  v_subject          := trim(p_subject);
  v_vars             := COALESCE(p_template_vars, '{}'::jsonb);

  INSERT INTO public.email_outbox (
    recipient_email, recipient_user_id, template_key,
    subject, template_vars, idempotency_key
  ) VALUES (
    v_email_normalised, p_recipient_user_id, p_template_key,
    v_subject, v_vars, p_idempotency_key
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  SELECT id INTO v_id
    FROM public.email_outbox
   WHERE idempotency_key = p_idempotency_key
   LIMIT 1;

  IF v_id IS NULL THEN
    -- Should be unreachable — ON CONFLICT DO NOTHING landed but SELECT
    -- still returns nothing. Surface as INTERNAL so we catch it.
    RAISE EXCEPTION 'INTERNAL: fn_enqueue_email could not locate row for key=%', p_idempotency_key
      USING ERRCODE = 'P0010';
  END IF;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.fn_enqueue_email(text, uuid, text, text, jsonb, text) IS
  'L15-04: idempotent enqueue of a transactional email. Returns the outbox '
  'row id (either newly-inserted or pre-existing with the same idempotency_key). '
  'Callers never see 23505 — safe in retry loops. Mutates status only via '
  'fn_mark_email_sent/fn_mark_email_failed after this call.';

REVOKE ALL ON FUNCTION public.fn_enqueue_email(text, uuid, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_enqueue_email(text, uuid, text, text, jsonb, text) TO service_role;

-- 3. fn_mark_email_sent -------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_mark_email_sent(
  p_id                  uuid,
  p_provider            text,
  p_provider_message_id text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status text;
  v_updated int;
BEGIN
  IF p_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ID: p_id is required' USING ERRCODE = '22023';
  END IF;
  IF p_provider IS NULL OR length(trim(p_provider)) = 0 THEN
    RAISE EXCEPTION 'INVALID_PROVIDER: p_provider is required' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_status
    FROM public.email_outbox
   WHERE id = p_id
   FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: email_outbox id=% does not exist', p_id
      USING ERRCODE = 'P0010';
  END IF;

  IF v_status = 'sent' THEN
    RETURN TRUE;
  END IF;

  IF v_status IN ('failed','suppressed') THEN
    RAISE EXCEPTION 'INVALID_TRANSITION: cannot mark % row as sent (id=%)', v_status, p_id
      USING ERRCODE = 'P0010';
  END IF;

  UPDATE public.email_outbox
     SET status              = 'sent',
         provider            = p_provider,
         provider_message_id = p_provider_message_id,
         sent_at             = now(),
         updated_at          = now(),
         last_error          = NULL
   WHERE id = p_id
     AND status IN ('pending','sending');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

COMMENT ON FUNCTION public.fn_mark_email_sent(uuid, text, text) IS
  'L15-04: idempotent terminal success transition. Flips status to sent and '
  'snapshots provider metadata. Returns TRUE when row already was or just '
  'became sent. Raises on invalid transition (failed/suppressed → sent).';

REVOKE ALL ON FUNCTION public.fn_mark_email_sent(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mark_email_sent(uuid, text, text) TO service_role;

-- 4. fn_mark_email_failed -----------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_mark_email_failed(
  p_id       uuid,
  p_error    text,
  p_terminal boolean DEFAULT false
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status   text;
  v_updated  int;
  v_new_st   text;
  v_error    text;
BEGIN
  IF p_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ID: p_id is required' USING ERRCODE = '22023';
  END IF;

  v_error := COALESCE(LEFT(NULLIF(trim(p_error), ''), 2000), 'unknown_error');

  SELECT status INTO v_status
    FROM public.email_outbox
   WHERE id = p_id
   FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: email_outbox id=% does not exist', p_id
      USING ERRCODE = 'P0010';
  END IF;

  IF v_status = 'failed' THEN
    RETURN TRUE;
  END IF;

  IF v_status IN ('sent','suppressed') THEN
    RAISE EXCEPTION 'INVALID_TRANSITION: cannot mark % row as failed (id=%)', v_status, p_id
      USING ERRCODE = 'P0010';
  END IF;

  IF p_terminal THEN
    v_new_st := 'failed';
    UPDATE public.email_outbox
       SET status     = v_new_st,
           failed_at  = now(),
           updated_at = now(),
           attempts   = attempts + 1,
           last_error = v_error
     WHERE id = p_id
       AND status IN ('pending','sending');
  ELSE
    v_new_st := 'pending';
    UPDATE public.email_outbox
       SET status     = v_new_st,
           updated_at = now(),
           attempts   = attempts + 1,
           last_error = v_error
     WHERE id = p_id
       AND status IN ('pending','sending');
  END IF;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

COMMENT ON FUNCTION public.fn_mark_email_failed(uuid, text, boolean) IS
  'L15-04: records a delivery failure. If p_terminal = TRUE (e.g. bounce, '
  'invalid address, 4xx provider rejection), flips status to failed. '
  'Otherwise bumps attempts + last_error and keeps status=pending so a '
  'retry loop can pick the row up again. Raises on invalid transition '
  '(sent/suppressed → failed).';

REVOKE ALL ON FUNCTION public.fn_mark_email_failed(uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mark_email_failed(uuid, text, boolean) TO service_role;

-- 5. fn_email_outbox_assert_shape --------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_email_outbox_assert_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_ok      boolean;
  v_funcs   int;
BEGIN
  -- 5.1 table + RLS forced
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
     WHERE n.nspname = 'public' AND c.relname = 'email_outbox'
       AND c.relrowsecurity AND c.relforcerowsecurity
  ) THEN
    v_missing := array_append(v_missing, 'table:email_outbox(rls_forced)');
  END IF;

  -- 5.2 UNIQUE index on idempotency_key
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
     WHERE c.relname = 'email_outbox_idempotency_key_uniq' AND i.indisunique
  ) THEN
    v_missing := array_append(v_missing, 'index:email_outbox_idempotency_key_uniq');
  END IF;

  -- 5.3 CHECK constraints
  SELECT (
      EXISTS(SELECT 1 FROM pg_constraint WHERE conname='email_outbox_status_check' AND conrelid='public.email_outbox'::regclass)
      AND EXISTS(SELECT 1 FROM pg_constraint WHERE conname='email_outbox_recipient_email_check' AND conrelid='public.email_outbox'::regclass)
      AND EXISTS(SELECT 1 FROM pg_constraint WHERE conname='email_outbox_template_key_check' AND conrelid='public.email_outbox'::regclass)
      AND EXISTS(SELECT 1 FROM pg_constraint WHERE conname='email_outbox_idempotency_key_check' AND conrelid='public.email_outbox'::regclass)
      AND EXISTS(SELECT 1 FROM pg_constraint WHERE conname='email_outbox_attempts_check' AND conrelid='public.email_outbox'::regclass)
  ) INTO v_ok;
  IF NOT v_ok THEN
    v_missing := array_append(v_missing, 'checks:email_outbox_*');
  END IF;

  -- 5.4 Functions registered with SECURITY DEFINER
  SELECT COUNT(*) INTO v_funcs
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
     AND p.proname IN (
       'fn_enqueue_email',
       'fn_mark_email_sent',
       'fn_mark_email_failed',
       'fn_email_outbox_assert_shape'
     )
     AND p.prosecdef;
  IF v_funcs <> 4 THEN
    v_missing := array_append(v_missing, format('functions:expected 4 SECURITY DEFINER helpers, found %s', v_funcs));
  END IF;

  -- 5.5 Privilege: anon/authenticated NOT EXECUTE on the three mutating helpers
  IF has_function_privilege('anon', 'public.fn_enqueue_email(text,uuid,text,text,jsonb,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fn_enqueue_email(text,uuid,text,text,jsonb,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_mark_email_sent(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fn_mark_email_sent(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_mark_email_failed(uuid,text,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fn_mark_email_failed(uuid,text,boolean)', 'EXECUTE')
  THEN
    v_missing := array_append(v_missing, 'privilege:anon_or_authenticated_has_execute');
  END IF;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'L15-04: email_outbox shape missing: %', array_to_string(v_missing, ', ')
      USING ERRCODE = 'P0010',
            HINT = 'See docs/runbooks/EMAIL_TRANSACTIONAL_RUNBOOK.md §3';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.fn_email_outbox_assert_shape() IS
  'L15-04: CI helper — raises P0010 if the email outbox invariants drift '
  '(missing table, missing UNIQUE, CHECK constraint dropped, helper functions '
  'missing, or anon/authenticated acquired EXECUTE). Used by '
  'npm run audit:email-platform.';

REVOKE ALL ON FUNCTION public.fn_email_outbox_assert_shape() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_email_outbox_assert_shape() TO service_role;

COMMIT;

-- ============================================================================
-- 6. Self-test — validates install + behaviour end-to-end
-- ============================================================================
DO $selftest$
DECLARE
  v_id_a    uuid;
  v_id_b    uuid;
  v_key_a   text := 'l15-04-selftest-' || gen_random_uuid()::text;
  v_key_b   text := 'l15-04-selftest-' || gen_random_uuid()::text;
  v_ok      boolean;
  v_status  text;
  v_attempts int;
BEGIN
  -- 6.0 shape assert passes
  PERFORM public.fn_email_outbox_assert_shape();

  -- 6.1 enqueue new
  v_id_a := public.fn_enqueue_email(
    'SELFTEST@Example.com', NULL, 'l15_04_selftest',
    'subject A', '{"name":"Alice"}'::jsonb, v_key_a
  );
  IF v_id_a IS NULL THEN
    RAISE EXCEPTION '[L15-04.selftest] enqueue returned NULL';
  END IF;

  -- 6.2 recipient normalised lower(trim())
  SELECT recipient_email INTO v_status FROM public.email_outbox WHERE id = v_id_a;
  IF v_status <> 'selftest@example.com' THEN
    RAISE EXCEPTION '[L15-04.selftest] recipient_email not normalised, got %', v_status;
  END IF;

  -- 6.3 enqueue same key → same row id
  v_id_b := public.fn_enqueue_email(
    'different@example.com', NULL, 'l15_04_selftest',
    'different subject', '{"name":"different"}'::jsonb, v_key_a
  );
  IF v_id_b <> v_id_a THEN
    RAISE EXCEPTION '[L15-04.selftest] same idempotency_key should return same id (got % vs %)', v_id_a, v_id_b;
  END IF;

  -- 6.4 enqueue different key → different row
  v_id_b := public.fn_enqueue_email(
    'second@example.com', NULL, 'l15_04_selftest',
    'subject B', '{}'::jsonb, v_key_b
  );
  IF v_id_b = v_id_a THEN
    RAISE EXCEPTION '[L15-04.selftest] different key should return different id';
  END IF;

  -- 6.5 mark_email_failed (non-terminal) bumps attempts, status stays pending
  v_ok := public.fn_mark_email_failed(v_id_a, 'provider 503', false);
  IF NOT v_ok THEN
    RAISE EXCEPTION '[L15-04.selftest] first non-terminal fail should return TRUE';
  END IF;
  SELECT status, attempts INTO v_status, v_attempts FROM public.email_outbox WHERE id = v_id_a;
  IF v_status <> 'pending' OR v_attempts <> 1 THEN
    RAISE EXCEPTION '[L15-04.selftest] after non-terminal fail expected pending/1, got %/%', v_status, v_attempts;
  END IF;

  -- 6.6 mark_email_sent flips to sent
  v_ok := public.fn_mark_email_sent(v_id_a, 'inbucket', 'msg-abc');
  IF NOT v_ok THEN
    RAISE EXCEPTION '[L15-04.selftest] mark_email_sent should return TRUE';
  END IF;
  SELECT status INTO v_status FROM public.email_outbox WHERE id = v_id_a;
  IF v_status <> 'sent' THEN
    RAISE EXCEPTION '[L15-04.selftest] expected sent, got %', v_status;
  END IF;

  -- 6.7 mark_email_sent idempotent (already sent → TRUE)
  v_ok := public.fn_mark_email_sent(v_id_a, 'inbucket', 'msg-abc');
  IF NOT v_ok THEN
    RAISE EXCEPTION '[L15-04.selftest] second mark_email_sent should return TRUE (idempotent)';
  END IF;

  -- 6.8 sent → failed transition raises
  BEGIN
    PERFORM public.fn_mark_email_failed(v_id_a, 'late bounce', true);
    RAISE EXCEPTION '[L15-04.selftest] sent → failed should have raised';
  EXCEPTION WHEN sqlstate 'P0010' THEN
    NULL;
  END;

  -- 6.9 terminal failure on pending row flips to failed
  v_ok := public.fn_mark_email_failed(v_id_b, 'invalid address', true);
  IF NOT v_ok THEN
    RAISE EXCEPTION '[L15-04.selftest] terminal fail should return TRUE';
  END IF;
  SELECT status INTO v_status FROM public.email_outbox WHERE id = v_id_b;
  IF v_status <> 'failed' THEN
    RAISE EXCEPTION '[L15-04.selftest] expected failed, got %', v_status;
  END IF;

  -- 6.10 failed → sent transition raises
  BEGIN
    PERFORM public.fn_mark_email_sent(v_id_b, 'resend', 'msg-def');
    RAISE EXCEPTION '[L15-04.selftest] failed → sent should have raised';
  EXCEPTION WHEN sqlstate 'P0010' THEN
    NULL;
  END;

  -- 6.11 argument validation: empty email rejected
  BEGIN
    PERFORM public.fn_enqueue_email('  ', NULL, 'x', 's', '{}'::jsonb,
      'l15-04-selftest-empty-' || gen_random_uuid()::text);
    RAISE EXCEPTION '[L15-04.selftest] empty recipient should have raised';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- 6.12 argument validation: idempotency_key < 8 chars rejected
  BEGIN
    PERFORM public.fn_enqueue_email('test@example.com', NULL, 'x', 's',
      '{}'::jsonb, 'short');
    RAISE EXCEPTION '[L15-04.selftest] short idempotency_key should have raised';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- Cleanup
  DELETE FROM public.email_outbox WHERE idempotency_key IN (v_key_a, v_key_b);

  RAISE NOTICE '[L15-04.selftest] OK — all invariants pass';
END
$selftest$;
