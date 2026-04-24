-- L01-49 — portal_audit_log.actor_id supports system actors
--
-- Antes: actor_id UUID NOT NULL REFERENCES auth.users(id).
-- Código TS chamava auditLog({ actorId: "system", ... }) para
-- ações automáticas (clearing.settle, webhook replays). O cast
-- para UUID falhava e o INSERT era perdido (logger.error apenas).
-- Resultado: auditoria silenciosamente incompleta.
--
-- Depois:
--   • actor_kind ('user' | 'system') NOT NULL DEFAULT 'user'
--   • actor_id agora NULLABLE
--   • CHECK: actor_kind='user' ⇒ actor_id NOT NULL
--           actor_kind='system' ⇒ actor_id IS NULL
--   • backfill: linhas existentes ⇒ actor_kind='user' (mantém FK)
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

ALTER TABLE public.portal_audit_log
  ADD COLUMN IF NOT EXISTS actor_kind text NOT NULL DEFAULT 'user';

ALTER TABLE public.portal_audit_log
  ALTER COLUMN actor_id DROP NOT NULL;

DO $cnstr$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'portal_audit_log_actor_kind_chk'
  ) THEN
    ALTER TABLE public.portal_audit_log
      ADD CONSTRAINT portal_audit_log_actor_kind_chk
      CHECK (
        (actor_kind = 'user'   AND actor_id IS NOT NULL) OR
        (actor_kind = 'system' AND actor_id IS NULL)
      );
  END IF;
END;
$cnstr$;

CREATE INDEX IF NOT EXISTS idx_portal_audit_actor_kind
  ON public.portal_audit_log (actor_kind, created_at DESC)
  WHERE actor_kind = 'system';

COMMENT ON COLUMN public.portal_audit_log.actor_kind IS
  'L01-49: ''user'' (actor_id FK to auth.users) or ''system'' (actor_id NULL); '
  'system entries cover async/background jobs (clearing settlement, webhook '
  'replays, scheduled tasks).';

DO $self$
DECLARE
  v_chk_ok boolean;
BEGIN
  SELECT count(*) > 0 INTO v_chk_ok
  FROM pg_constraint
  WHERE conname = 'portal_audit_log_actor_kind_chk';
  IF NOT v_chk_ok THEN
    RAISE EXCEPTION 'L01-49 self-test: CHECK constraint missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='portal_audit_log'
      AND column_name='actor_id' AND is_nullable='NO'
  ) THEN
    RAISE EXCEPTION 'L01-49 self-test: actor_id still NOT NULL';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='portal_audit_log'
      AND column_name='actor_kind'
  ) THEN
    RAISE EXCEPTION 'L01-49 self-test: actor_kind column missing';
  END IF;

  RAISE NOTICE 'L01-49 self-test PASSED';
END;
$self$;

COMMIT;
