-- ============================================================================
-- L04-02 / L01-36 / L06-08 — Persistent audit trail for self-account deletion
-- ============================================================================
--
-- Why a dedicated table (not portal_audit_log)?
--
--   1. portal_audit_log.actor_id has a NOT NULL FK to auth.users(id) without
--      ON DELETE — once we delete the auth user the FK breaks (or the row
--      becomes inaccessible). For LGPD self-deletion we MUST keep the trail
--      after the user vanishes.
--
--   2. We need to bind a record to an *email_hash* (SHA-256 of the user's
--      lowercased email at deletion time) so a future ANPD inquiry can prove
--      "this email-bound account was deleted on date X" without retaining
--      the email itself (PII).
--
--   3. The deletion flow has multiple sub-failures (cleanup err vs auth-
--      delete err vs both); we want a single immutable timeline of every
--      attempt, including failures, with structured outcome.
--
-- The table is append-mostly: rows are INSERTed at the start of a deletion
-- attempt and (optionally) UPDATED once on completion to record the
-- terminal outcome. UPDATEs are restricted to:
--
--   - completed_at        (set once, immutable thereafter)
--   - failure_reason      (set once, immutable thereafter)
--   - cleanup_report      (set once, immutable thereafter)
--   - outcome             (set once, immutable thereafter)
--
-- Enforced via the trigger `account_deletion_log_immutable_after_completion`.
--
-- DELETE is rejected for everyone except superuser (handled at GRANT level
-- by REVOKE DELETE FROM PUBLIC).

CREATE TABLE IF NOT EXISTS public.account_deletion_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Request id from the edge function — primary correlation key against
  -- structured logs (logRequest/logError) and Sentry traces.
  request_id      uuid NOT NULL UNIQUE,
  -- The user_id at the time of the request. After auth.users row is gone
  -- this reference becomes a soft id only. We deliberately do NOT add a
  -- FK so the trail survives the deletion it documents.
  user_id         uuid NOT NULL,
  -- SHA-256 hex digest of the lowercased, trimmed email at request time.
  -- 64 hex chars; CHECK constraint enforces shape so a malformed write
  -- (truncation, plain email leak) is rejected at the DB.
  email_hash      text NOT NULL CHECK (email_hash ~ '^[0-9a-f]{64}$'),
  -- Snapshot of the user's role (athlete / professor / admin_master) for
  -- post-mortem segmentation. NULL allowed if profile lookup failed.
  user_role       text,
  initiated_at    timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,
  -- Terminal outcome. NULL while the attempt is in flight. The trigger
  -- below ensures a non-NULL outcome cannot be overwritten.
  outcome         text CHECK (outcome IN (
    'success',
    'cleanup_failed',
    'auth_delete_failed',
    'cancelled_by_validation',
    'internal_error'
  )),
  -- Free-form failure context (truncated). Never PII; populated from
  -- Postgres SQLERRM or the auth admin error message.
  failure_reason  text,
  -- jsonb report from `fn_delete_user_data` (per-table row counts).
  -- Captured BEFORE auth.users is deleted so SAR responses can quote it.
  cleanup_report  jsonb,
  -- Best-effort client identification (IP, UA truncated). We deliberately
  -- avoid storing the JWT, request body, or any field beyond what the
  -- HTTP layer surfaces in standard headers. NULL when unknown.
  client_ip       inet,
  client_ua       text CHECK (client_ua IS NULL OR length(client_ua) <= 500)
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_log_user
  ON public.account_deletion_log (user_id);

CREATE INDEX IF NOT EXISTS idx_account_deletion_log_email_hash
  ON public.account_deletion_log (email_hash);

CREATE INDEX IF NOT EXISTS idx_account_deletion_log_outcome_partial
  ON public.account_deletion_log (initiated_at DESC)
  WHERE outcome IN ('cleanup_failed', 'auth_delete_failed', 'internal_error');

COMMENT ON TABLE public.account_deletion_log IS
  'Immutable trail of LGPD Art. 18 self-deletion requests. Survives the deletion of the underlying auth.users row. See L04-02 / L06-08.';

-- ── Immutability trigger ────────────────────────────────────────────────────
--
-- Once outcome / completed_at / failure_reason / cleanup_report are set
-- (terminal state), they cannot be overwritten. The initial INSERT sets
-- them to NULL; a single follow-up UPDATE writes the terminal values.
-- Subsequent UPDATEs that try to change non-NULL terminal columns are
-- rejected.

CREATE OR REPLACE FUNCTION public.fn_account_deletion_log_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.id           IS DISTINCT FROM NEW.id           OR
     OLD.request_id   IS DISTINCT FROM NEW.request_id   OR
     OLD.user_id      IS DISTINCT FROM NEW.user_id      OR
     OLD.email_hash   IS DISTINCT FROM NEW.email_hash   OR
     OLD.initiated_at IS DISTINCT FROM NEW.initiated_at OR
     OLD.user_role    IS DISTINCT FROM NEW.user_role    OR
     OLD.client_ip    IS DISTINCT FROM NEW.client_ip    OR
     OLD.client_ua    IS DISTINCT FROM NEW.client_ua
  THEN
    RAISE EXCEPTION 'account_deletion_log: identity / context columns are immutable'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.outcome IS NOT NULL AND OLD.outcome IS DISTINCT FROM NEW.outcome THEN
    RAISE EXCEPTION 'account_deletion_log: outcome is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.completed_at IS NOT NULL AND OLD.completed_at IS DISTINCT FROM NEW.completed_at THEN
    RAISE EXCEPTION 'account_deletion_log: completed_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.failure_reason IS NOT NULL AND OLD.failure_reason IS DISTINCT FROM NEW.failure_reason THEN
    RAISE EXCEPTION 'account_deletion_log: failure_reason is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.cleanup_report IS NOT NULL AND OLD.cleanup_report IS DISTINCT FROM NEW.cleanup_report THEN
    RAISE EXCEPTION 'account_deletion_log: cleanup_report is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS account_deletion_log_immutable
  ON public.account_deletion_log;

CREATE TRIGGER account_deletion_log_immutable
  BEFORE UPDATE ON public.account_deletion_log
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_account_deletion_log_immutable();

-- ── RLS ─────────────────────────────────────────────────────────────────────
--
-- service_role (edge functions) writes everything; admin_master reads only
-- their own cohort would be wrong (no group context for an athlete leaving
-- the platform). Restrict reads to platform_role='admin' only — these are
-- the operators that handle ANPD inquiries.

ALTER TABLE public.account_deletion_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS account_deletion_log_platform_admin_read
  ON public.account_deletion_log;

CREATE POLICY account_deletion_log_platform_admin_read
  ON public.account_deletion_log
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
       WHERE id = auth.uid()
         AND platform_role = 'admin'
    )
  );

-- service_role bypasses RLS — no INSERT / UPDATE policy needed for it.

REVOKE DELETE ON public.account_deletion_log FROM PUBLIC, authenticated, anon;

COMMENT ON COLUMN public.account_deletion_log.email_hash IS
  'SHA-256(lowercase(trim(email))) at deletion time. Never store the raw email here.';

COMMENT ON COLUMN public.account_deletion_log.outcome IS
  'Terminal outcome of the deletion attempt. NULL while in flight. Immutable once set.';
