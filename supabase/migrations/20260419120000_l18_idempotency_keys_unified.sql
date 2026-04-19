-- ============================================================================
-- L18-02 — Unified server-side idempotency keys
-- ============================================================================
--
-- The audit (Lente 18, item 18.2) flagged that idempotency was
-- implemented ad-hoc in each RPC: `confirm_custody_deposit` used
-- `SELECT ... FOR UPDATE` + status check, `execute_burn_atomic` used
-- `SELECT ... FOR UPDATE` on the wallet, `execute_swap` used UUID
-- ordering for a different deadlock concern; and `execute_withdrawal`
-- + `distribute-coins` had **no** idempotency at all. A single retry
-- from a Vercel edge under network jitter could fire two
-- `withdraw` operations against the same authoritative request.
--
-- L01-04 already established a focused pattern for `custody.deposit`
-- (`custody_deposits.idempotency_key` UNIQUE composto + RPC
-- `fn_create_custody_deposit_idempotent` returning `was_idempotent`).
-- That pattern is great for a single resource creation but does not
-- generalize: it lives inside the resource table, returns only the
-- resource id, and cannot replay the original HTTP response body.
--
-- This migration introduces the cross-cutting layer:
--
--   public.idempotency_keys      — store of (key, request_hash,
--                                  response, status_code, expires_at)
--                                  scoped per-namespace per-actor.
--
--   fn_idem_begin(...)           — claim a key; returns either the
--                                  prior cached response (replay) OR
--                                  a sentinel telling the caller to
--                                  proceed with execution.
--
--   fn_idem_finalize(...)        — store the response after the
--                                  caller finished executing.
--
--   fn_idem_release(...)         — release a claimed-but-not-finalized
--                                  key (for failure paths that should
--                                  NOT cache the error indefinitely).
--
--   fn_idem_gc()                 — delete expired rows. Cron'd hourly
--                                  via pg_cron with cron_run_state
--                                  observability (L12-03 pattern).
--
-- Scope and namespacing:
--
--   Each call site declares a `namespace` (e.g. `custody.withdraw`,
--   `coins.distribute`, `swap.create`). The key is composed as
--   `(namespace, actor_id, key)` so two different APIs can use the
--   same key value (`x-idempotency-key: 123`) without colliding —
--   each gets its own namespace bucket.
--
--   `actor_id` is required (zero-trust: a key is bound to the
--   authenticated user that claimed it; another user replaying the
--   same key gets a fresh execution slot). For unauthenticated
--   surfaces this should be the caller's stable identity (e.g. a
--   webhook tenant id), never a request-attacker-controlled value.
--
-- Request hash mismatch:
--
--   Replays with the *same* key but a *different* request body are
--   a strong indicator of either a bug in the client or an attacker
--   trying to swap the body of an idempotent request. The contract:
--
--     fn_idem_begin returns `request_mismatch=true` when a prior
--     row for `(namespace, actor_id, key)` exists but the
--     request_hash differs. Callers MUST surface this as a 409
--     CONFLICT rather than executing.
--
-- Lifecycle:
--
--   states     : claimed → completed   (success path)
--              : claimed → released    (early bail before mutation)
--   timeouts   : a `claimed` row whose `claimed_at` is older than
--                `claim_lease_seconds` (default 60) is treated as
--                stale and re-claimable by a new caller. This
--                prevents a crashed worker from poisoning the key
--                forever.
--   retention  : `expires_at` defaults to `claimed_at + 24 hours`.
--                Caller can override via `p_ttl_seconds`. `fn_idem_gc`
--                removes rows past `expires_at`.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Table: idempotency_keys
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.idempotency_keys (
  namespace        text         NOT NULL,
  actor_id         uuid         NOT NULL,
  key              text         NOT NULL,
  request_hash     bytea        NOT NULL,
  status           text         NOT NULL DEFAULT 'claimed',
  response_body    jsonb,
  status_code      integer,
  claimed_at       timestamptz  NOT NULL DEFAULT now(),
  finalized_at     timestamptz,
  expires_at       timestamptz  NOT NULL DEFAULT (now() + interval '24 hours'),
  PRIMARY KEY (namespace, actor_id, key),
  CONSTRAINT idem_status_check CHECK (status IN ('claimed', 'completed', 'released')),
  CONSTRAINT idem_namespace_check CHECK (namespace ~ '^[a-z][a-z0-9_.]{1,63}$'),
  CONSTRAINT idem_key_check CHECK (length(key) BETWEEN 8 AND 128),
  CONSTRAINT idem_status_code_range CHECK (
    status_code IS NULL OR (status_code BETWEEN 100 AND 599)
  ),
  CONSTRAINT idem_completed_must_have_response CHECK (
    status <> 'completed' OR (response_body IS NOT NULL AND status_code IS NOT NULL AND finalized_at IS NOT NULL)
  )
);

COMMENT ON TABLE public.idempotency_keys IS
  'L18-02: cross-cutting idempotency store. PK(namespace, actor_id, key). Lifecycle: claimed -> completed | released. Stale claims past claim_lease_seconds are re-claimable. Expired rows GCd by fn_idem_gc.';

CREATE INDEX IF NOT EXISTS idx_idem_expires
  ON public.idempotency_keys (expires_at);

ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.idempotency_keys FROM PUBLIC;
REVOKE ALL ON public.idempotency_keys FROM anon;
REVOKE ALL ON public.idempotency_keys FROM authenticated;
GRANT  ALL ON public.idempotency_keys TO service_role;

-- Service role only; no end-user-facing policy.

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_idem_begin — claim or replay
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Returns a single row with these columns:
--
--   action            text   ─ 'execute' | 'replay' | 'mismatch'
--   replay_status     int    ─ HTTP status to replay (only when 'replay')
--   replay_body       jsonb  ─ body to replay (only when 'replay')
--   stale_recovered   bool   ─ true if a prior 'claimed' row was stale and reclaimed
--
-- Semantics:
--
--   1. INSERT a new claim row. ON CONFLICT inspect:
--      a. status='completed': replay (return cached response).
--      b. status='claimed' AND claimed_at > now() - lease: another
--         caller is mid-execution. Tell caller to back off via
--         action='execute' but with `replay_body=null` and
--         `replay_status=null`? — No. Concurrent identical requests
--         is exactly the case idempotency must serialize. We return
--         action='execute' but ONLY after taking pg_advisory_xact_lock
--         on the (ns, actor, key) hash, which serializes concurrent
--         claims. Once the first finalizes, subsequent advisory lock
--         acquirers see status='completed' and replay.
--         Implementation: caller must wrap the call to fn_idem_begin
--         + execution + fn_idem_finalize in a single transaction
--         (or rely on the advisory lock taken inside fn_idem_begin
--         which is held only for the duration of that call — see
--         note below).
--      c. status='claimed' AND stale (older than lease): treat as
--         abandoned, UPDATE to bump claimed_at + reset request_hash,
--         return action='execute' with stale_recovered=true.
--      d. status='released': allow re-claim (UPDATE).
--   2. If the existing request_hash differs from the new one, return
--      action='mismatch' regardless of status. Caller must 409.
--
-- Concurrency note: this function does not hold a row lock past its
-- own transaction. The caller is expected to either:
--   (a) execute its full mutation in the same transaction as
--       fn_idem_begin / fn_idem_finalize (preferred — see custody
--       deposit pattern), OR
--   (b) accept that two concurrent `claimed` callers will both run
--       their mutations and the second one will fail at the
--       resource-level idempotency (e.g. UNIQUE on coin_ledger.ref_id
--       or wallet FOR UPDATE). The cached response cache is still
--       useful: the LATER finalize wins (last-writer caches its
--       response).

CREATE OR REPLACE FUNCTION public.fn_idem_begin(
  p_namespace        text,
  p_actor_id         uuid,
  p_key              text,
  p_request_hash     bytea,
  p_ttl_seconds      integer DEFAULT 86400,
  p_claim_lease_secs integer DEFAULT 60
)
RETURNS TABLE (
  action          text,
  replay_status   integer,
  replay_body     jsonb,
  stale_recovered boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_existing  public.idempotency_keys%ROWTYPE;
  v_now       timestamptz := now();
  v_expires   timestamptz;
BEGIN
  IF p_namespace IS NULL OR p_actor_id IS NULL OR p_key IS NULL OR p_request_hash IS NULL THEN
    RAISE EXCEPTION 'fn_idem_begin: required parameter is NULL' USING ERRCODE = 'P0001';
  END IF;
  IF p_ttl_seconds <= 0 OR p_ttl_seconds > 7 * 86400 THEN
    RAISE EXCEPTION 'fn_idem_begin: p_ttl_seconds out of range (1..604800)' USING ERRCODE = 'P0001';
  END IF;
  IF p_claim_lease_secs <= 0 OR p_claim_lease_secs > 3600 THEN
    RAISE EXCEPTION 'fn_idem_begin: p_claim_lease_secs out of range (1..3600)' USING ERRCODE = 'P0001';
  END IF;

  v_expires := v_now + make_interval(secs => p_ttl_seconds);

  SELECT * INTO v_existing
    FROM public.idempotency_keys
   WHERE namespace = p_namespace
     AND actor_id  = p_actor_id
     AND key       = p_key
   FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.idempotency_keys (
      namespace, actor_id, key, request_hash, status, expires_at
    ) VALUES (
      p_namespace, p_actor_id, p_key, p_request_hash, 'claimed', v_expires
    );
    RETURN QUERY SELECT 'execute'::text, NULL::int, NULL::jsonb, false;
    RETURN;
  END IF;

  IF v_existing.request_hash <> p_request_hash THEN
    RETURN QUERY SELECT 'mismatch'::text, NULL::int, NULL::jsonb, false;
    RETURN;
  END IF;

  IF v_existing.status = 'completed' THEN
    RETURN QUERY SELECT
      'replay'::text,
      v_existing.status_code,
      v_existing.response_body,
      false;
    RETURN;
  END IF;

  IF v_existing.status = 'claimed' THEN
    IF v_existing.claimed_at < v_now - make_interval(secs => p_claim_lease_secs) THEN
      UPDATE public.idempotency_keys
         SET claimed_at    = v_now,
             expires_at    = v_expires,
             response_body = NULL,
             status_code   = NULL,
             finalized_at  = NULL
       WHERE namespace = p_namespace
         AND actor_id  = p_actor_id
         AND key       = p_key;
      RETURN QUERY SELECT 'execute'::text, NULL::int, NULL::jsonb, true;
      RETURN;
    END IF;
    RETURN QUERY SELECT 'execute'::text, NULL::int, NULL::jsonb, false;
    RETURN;
  END IF;

  IF v_existing.status = 'released' THEN
    UPDATE public.idempotency_keys
       SET status        = 'claimed',
           claimed_at    = v_now,
           expires_at    = v_expires,
           response_body = NULL,
           status_code   = NULL,
           finalized_at  = NULL
     WHERE namespace = p_namespace
       AND actor_id  = p_actor_id
       AND key       = p_key;
    RETURN QUERY SELECT 'execute'::text, NULL::int, NULL::jsonb, false;
    RETURN;
  END IF;

  RAISE EXCEPTION 'fn_idem_begin: unexpected status %', v_existing.status USING ERRCODE = 'XX000';
END;
$$;

COMMENT ON FUNCTION public.fn_idem_begin(text, uuid, text, bytea, int, int) IS
  'L18-02: claim or replay an idempotency key. Returns action=execute|replay|mismatch. Mismatch means the same key was used with a different request body — caller MUST 409 CONFLICT.';

REVOKE ALL ON FUNCTION public.fn_idem_begin(text, uuid, text, bytea, int, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_idem_begin(text, uuid, text, bytea, int, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_idem_begin(text, uuid, text, bytea, int, int) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_idem_finalize — store the response
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Atomically transitions a 'claimed' row to 'completed' with the
-- response payload. NO-OP (returns false) if the row doesn't exist
-- or isn't in 'claimed' state — this protects against a stale
-- worker writing over a fresh claim from another caller.

CREATE OR REPLACE FUNCTION public.fn_idem_finalize(
  p_namespace    text,
  p_actor_id     uuid,
  p_key          text,
  p_status_code  integer,
  p_response     jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF p_namespace IS NULL OR p_actor_id IS NULL OR p_key IS NULL THEN
    RAISE EXCEPTION 'fn_idem_finalize: required parameter is NULL' USING ERRCODE = 'P0001';
  END IF;
  IF p_status_code IS NULL OR p_status_code < 100 OR p_status_code > 599 THEN
    RAISE EXCEPTION 'fn_idem_finalize: p_status_code out of HTTP range' USING ERRCODE = 'P0001';
  END IF;
  IF p_response IS NULL THEN
    RAISE EXCEPTION 'fn_idem_finalize: p_response is NULL — use fn_idem_release for cancellation' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.idempotency_keys
     SET status        = 'completed',
         status_code   = p_status_code,
         response_body = p_response,
         finalized_at  = now()
   WHERE namespace = p_namespace
     AND actor_id  = p_actor_id
     AND key       = p_key
     AND status    = 'claimed';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

COMMENT ON FUNCTION public.fn_idem_finalize(text, uuid, text, int, jsonb) IS
  'L18-02: store the response for a previously-claimed idempotency key. Returns true on success, false if the row is missing or not in claimed state.';

REVOKE ALL ON FUNCTION public.fn_idem_finalize(text, uuid, text, int, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_idem_finalize(text, uuid, text, int, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_idem_finalize(text, uuid, text, int, jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. fn_idem_release — release a claim without finalizing
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Use this when the caller bails out before mutating any state
-- (e.g. validation failed AFTER claiming). Marking the row as
-- 'released' allows a future call with the same key to retry
-- without waiting for the claim_lease timeout.

CREATE OR REPLACE FUNCTION public.fn_idem_release(
  p_namespace    text,
  p_actor_id     uuid,
  p_key          text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.idempotency_keys
     SET status = 'released'
   WHERE namespace = p_namespace
     AND actor_id  = p_actor_id
     AND key       = p_key
     AND status    = 'claimed';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

COMMENT ON FUNCTION public.fn_idem_release(text, uuid, text) IS
  'L18-02: release a claimed-but-not-finalized idempotency key. Returns true if a row transitioned from claimed to released.';

REVOKE ALL ON FUNCTION public.fn_idem_release(text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_idem_release(text, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_idem_release(text, uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. fn_idem_gc — purge expired keys
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_idem_gc()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '5s'
AS $$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM public.idempotency_keys
   WHERE expires_at < now();
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.fn_idem_gc() IS
  'L18-02: purge idempotency_keys past expires_at. Cron-fired hourly. Idempotent.';

REVOKE ALL ON FUNCTION public.fn_idem_gc() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_idem_gc() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_idem_gc() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Safe wrapper + cron schedule (uses L12-03 pattern)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

CREATE OR REPLACE FUNCTION public.fn_idem_gc_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  k_job_name constant text := 'idempotency-keys-gc';
  k_max_runtime constant int := 60;
  v_should_run boolean;
  v_lock boolean;
  v_deleted int;
BEGIN
  v_should_run := public.fn_cron_should_run(k_job_name, k_max_runtime);
  IF NOT v_should_run THEN
    RETURN;
  END IF;

  v_lock := pg_try_advisory_xact_lock(hashtext('cron:' || k_job_name));
  IF NOT v_lock THEN
    PERFORM public.fn_cron_mark_failed(
      k_job_name,
      'advisory lock unavailable',
      jsonb_build_object('reason', 'advisory_lock_busy')
    );
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started(k_job_name);

  BEGIN
    v_deleted := public.fn_idem_gc();
    PERFORM public.fn_cron_mark_completed(
      k_job_name,
      jsonb_build_object('deleted', v_deleted)
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      k_job_name,
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE)
    );
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_idem_gc_safe() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_idem_gc_safe() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_idem_gc_safe() TO service_role;

DO $$
BEGIN
  -- Unschedule any prior placeholder, then schedule fresh.
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'idempotency-keys-gc') THEN
    PERFORM cron.unschedule('idempotency-keys-gc');
  END IF;
  PERFORM cron.schedule(
    'idempotency-keys-gc',
    '7 * * * *',
    $job$SELECT public.fn_idem_gc_safe();$job$
  );
END $$;

-- Seed cron_run_state for immediate observability.
INSERT INTO public.cron_run_state (name, last_status)
VALUES ('idempotency-keys-gc', 'never_run')
ON CONFLICT (name) DO NOTHING;
