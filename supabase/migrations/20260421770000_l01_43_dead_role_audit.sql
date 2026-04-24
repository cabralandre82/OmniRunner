-- L01-43 — dead 'professor' role audit
--
-- Migration 20260303300000 drop+create-d the affected RLS policies
-- (custody_accounts, custody_deposits, clearing_events) replacing
-- the dead role 'professor' with the canonical 'coach'. This
-- migration adds a runtime self-test that asserts NO live policy
-- in pg_policies references 'professor' any longer, guaranteeing
-- the fix is effective at the production database level (not just
-- in source files).
--
-- OmniCoin policy: zero writes; pure introspection.
-- L04-07-OK

BEGIN;

DO $self$
DECLARE
  v_offenders text;
BEGIN
  SELECT string_agg(
           format('%I.%I/%I', schemaname, tablename, policyname),
           ', '
         )
  INTO v_offenders
  FROM pg_policies
  WHERE schemaname = 'public'
    AND (qual::text ILIKE '%''professor''%' OR with_check::text ILIKE '%''professor''%');

  IF v_offenders IS NOT NULL THEN
    RAISE EXCEPTION
      'L01-43 self-test: live policies still reference dead role ''professor'': %',
      v_offenders;
  END IF;

  RAISE NOTICE 'L01-43 self-test PASSED — no live policy references ''professor''';
END;
$self$;

COMMIT;
