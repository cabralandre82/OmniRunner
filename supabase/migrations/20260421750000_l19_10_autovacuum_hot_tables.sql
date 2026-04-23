-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ L19-10 — Autovacuum tuning for hot tables                                ║
-- ║                                                                          ║
-- ║ Tabelas em alto write/update precisam de autovacuum mais agressivo que  ║
-- ║ o default (scale_factor = 0.2 = 20% das tuplas mortas antes de rodar). ║
-- ║ Para tabelas que crescem 10k+ rows/dia, esperar 20% causa bloat.        ║
-- ║                                                                          ║
-- ║ Tabelas alvo (justificativa)                                            ║
-- ║ -----------------------------                                           ║
-- ║   • coin_ledger      — append-only mas FILE growth alto (cada           ║
-- ║                        challenge gera N ledger entries)                ║
-- ║   • sessions         — Strava sync diário; volume linear ao MAU         ║
-- ║   • product_events   — analytics/observability; alto write             ║
-- ║   • audit_logs       — security + compliance; cada API hit              ║
-- ║   • workout_delivery_items — coach assigns daily                        ║
-- ║   • workout_delivery_events — log de mudanças de status                ║
-- ║                                                                          ║
-- ║ OmniCoin policy: este migration apenas ajusta storage parameters;       ║
-- ║ não toca rows de coin_ledger nem wallets.                              ║
-- ║ L04-07-OK                                                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Apply settings only when the table actually exists.
--    Each block is idempotent and can be re-run safely.
-- ─────────────────────────────────────────────────────────────────────

DO $apply$
DECLARE
  v_tables text[] := ARRAY[
    'coin_ledger',
    'sessions',
    'product_events',
    'audit_logs',
    'workout_delivery_items',
    'workout_delivery_events'
  ];
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_table
    ) THEN
      EXECUTE format($f$
        ALTER TABLE public.%I SET (
          autovacuum_vacuum_scale_factor  = 0.05,
          autovacuum_analyze_scale_factor = 0.02,
          autovacuum_vacuum_cost_delay    = 10,
          autovacuum_vacuum_cost_limit    = 1000
        );
      $f$, v_table);
      RAISE NOTICE 'L19-10: autovacuum tuned for %', v_table;
    ELSE
      RAISE NOTICE 'L19-10: skipping % (table not present in this env)', v_table;
    END IF;
  END LOOP;
END;
$apply$;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Self-test: verify at least one of the tables actually got the
--    setting applied (non-empty options array containing scale factor).
-- ─────────────────────────────────────────────────────────────────────

DO $self$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN (
      'coin_ledger', 'sessions', 'product_events',
      'audit_logs', 'workout_delivery_items', 'workout_delivery_events'
    )
    AND EXISTS (
      SELECT 1 FROM unnest(c.reloptions) opt
      WHERE opt LIKE 'autovacuum_vacuum_scale_factor=0.05'
    );

  IF v_count = 0 THEN
    -- It's OK if NO table existed in this env (fresh dev DB), but if
    -- ANY existed it must have been tuned. Verify the inverse.
    IF EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname IN (
          'coin_ledger', 'sessions', 'product_events',
          'audit_logs', 'workout_delivery_items', 'workout_delivery_events'
        )
    ) THEN
      RAISE EXCEPTION 'L19-10 self-test: hot tables exist but none received autovacuum tuning';
    END IF;
  END IF;

  RAISE NOTICE 'L19-10 self-test PASSED (% hot tables tuned)', v_count;
END;
$self$;

COMMIT;
