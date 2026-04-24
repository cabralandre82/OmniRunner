-- L18-09 — typed/versioned domain events in audit_logs
--
-- Antes: audit_logs.action é text livre. "custody.deposit.confirmed"
-- ao lado de "user.login" sem distinção de domain/scope/version.
-- Consumidores precisam fazer string parsing frágil para descobrir
-- a estrutura do metadata.
--
-- Depois:
--   • event_schema_version int NOT NULL DEFAULT 1
--     - bump quando a forma do metadata mudar
--   • event_domain text   NOT NULL DEFAULT 'unknown'
--     - 'custody', 'wallet', 'auth', 'workout', 'challenge', 'system'…
--     - extraído de action via prefix split('.', 1)[0]
--   • CHECK garante que action sempre tem o formato "<domain>.<resource>.<verb>"
--   • backfill: existing rows ⇒ event_domain extraído do action
--
-- Aplica também ao portal_audit_log (mesmo padrão).
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

DO $apply$
DECLARE
  v_t text;
  v_targets text[] := ARRAY['audit_logs', 'portal_audit_log'];
BEGIN
  FOREACH v_t IN ARRAY v_targets LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname='public' AND c.relname=v_t AND c.relkind='r'
    ) THEN
      RAISE NOTICE 'L18-09: skip %, table not present', v_t;
      CONTINUE;
    END IF;

    EXECUTE format(
      'ALTER TABLE public.%I '
      '  ADD COLUMN IF NOT EXISTS event_schema_version int NOT NULL DEFAULT 1, '
      '  ADD COLUMN IF NOT EXISTS event_domain         text NOT NULL DEFAULT ''unknown''',
      v_t);

    EXECUTE format(
      'UPDATE public.%I '
      '   SET event_domain = COALESCE(NULLIF(split_part(action, ''.'', 1), ''''), ''unknown'') '
      ' WHERE event_domain = ''unknown''',
      v_t);

    -- CHECK: action must use dotted notation domain.resource.verb (or longer)
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = format('%s_action_dotted_chk', v_t)
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I '
        '  ADD CONSTRAINT %I '
        '  CHECK (action ~ ''^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]+)+$'') NOT VALID',
        v_t, format('%s_action_dotted_chk', v_t));
      -- NOT VALID + manual VALIDATE so legacy rows don't block migration.
      -- Operator validates after backfill in a maintenance window.
    END IF;

    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%I_domain_created '
      '  ON public.%I (event_domain, created_at DESC)',
      v_t, v_t);

    RAISE NOTICE 'L18-09: schema versioning applied to public.%', v_t;
  END LOOP;
END;
$apply$;

COMMENT ON COLUMN public.portal_audit_log.event_schema_version IS
  'L18-09: bump when metadata shape changes for a given action.';
COMMENT ON COLUMN public.portal_audit_log.event_domain IS
  'L18-09: first dotted-segment of action (custody, wallet, auth, ...). '
  'Backfilled from action.';

DO $self$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='portal_audit_log'
      AND column_name='event_schema_version'
  ) THEN
    RAISE EXCEPTION 'L18-09 self-test: portal_audit_log.event_schema_version missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='portal_audit_log'
      AND column_name='event_domain'
  ) THEN
    RAISE EXCEPTION 'L18-09 self-test: portal_audit_log.event_domain missing';
  END IF;
  RAISE NOTICE 'L18-09 self-test PASSED';
END;
$self$;

COMMIT;
