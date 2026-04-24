-- L03-15 — expire stale custody_deposits
--
-- Antes: custody_deposits.status='pending' nunca expira. Stripe/MP
-- pode enviar webhook tarde, ou nunca. Operação fica com lista
-- crescente de depósitos inconclusivos, dificultando reconciliação.
--
-- Depois:
--   • Adiciona status 'expired' (CHECK + COMMENT)
--   • RPC fn_expire_stale_deposits(p_max_age interval default '48 hours')
--     - SECURITY DEFINER, retorna count de rows updated
--     - apenas pending mais antigos que p_max_age
--     - never touches coin_ledger / wallets (depósito não foi creditado)
--   • Cron diário às 03:10 UTC, idempotente via cron.unschedule guard
--   • SLO: a expiração nunca deve aumentar custody_deposit invariants
--     porque o ledger ainda não foi creditado.
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

ALTER TABLE public.custody_deposits
  DROP CONSTRAINT IF EXISTS custody_deposits_status_check;

ALTER TABLE public.custody_deposits
  ADD CONSTRAINT custody_deposits_status_check
  CHECK (status IN ('pending', 'confirmed', 'failed', 'refunded', 'expired'));

ALTER TABLE public.custody_deposits
  ADD COLUMN IF NOT EXISTS expired_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_custody_deposits_pending_old
  ON public.custody_deposits (created_at)
  WHERE status = 'pending';

CREATE OR REPLACE FUNCTION public.fn_expire_stale_deposits(
  p_max_age interval DEFAULT interval '48 hours'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now      timestamptz := now();
  v_cutoff   timestamptz := v_now - p_max_age;
  v_expired  bigint;
  v_sample   uuid[];
BEGIN
  WITH up AS (
    UPDATE public.custody_deposits
       SET status     = 'expired',
           expired_at = v_now
     WHERE status     = 'pending'
       AND created_at < v_cutoff
     RETURNING id
  )
  SELECT count(*),
         COALESCE(array_agg(id), ARRAY[]::uuid[])
    INTO v_expired, v_sample
    FROM up;

  RETURN jsonb_build_object(
    'expired_count', v_expired,
    'cutoff',        v_cutoff,
    'max_age_hours', extract(epoch FROM p_max_age) / 3600,
    'ran_at',        v_now,
    'sample_ids',    to_jsonb(v_sample[1:5])
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_expire_stale_deposits(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_expire_stale_deposits(interval) TO service_role;

COMMENT ON FUNCTION public.fn_expire_stale_deposits(interval) IS
  'L03-15: marca custody_deposits ''pending'' como ''expired'' após interval. '
  'Default 48h. Nunca toca coin_ledger ou wallets (depósito ainda não creditou).';

DO $cron$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE NOTICE 'L03-15: pg_cron not installed; skipping cron registration. '
                 'Operator must invoke fn_expire_stale_deposits manually.';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'l03_15_expire_stale_deposits'
  ) THEN
    PERFORM cron.schedule(
      'l03_15_expire_stale_deposits',
      '10 3 * * *',
      $job$ SELECT public.fn_expire_stale_deposits(); $job$
    );
    RAISE NOTICE 'L03-15: cron l03_15_expire_stale_deposits scheduled (03:10 UTC daily)';
  END IF;
END;
$cron$;

DO $self$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_expire_stale_deposits'
  ) THEN
    RAISE EXCEPTION 'L03-15 self-test: fn_expire_stale_deposits missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'custody_deposits_status_check'
      AND pg_get_constraintdef(oid) LIKE '%expired%'
  ) THEN
    RAISE EXCEPTION 'L03-15 self-test: status CHECK does not include ''expired''';
  END IF;

  RAISE NOTICE 'L03-15 self-test PASSED';
END;
$self$;

COMMIT;
