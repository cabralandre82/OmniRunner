-- ============================================================================
-- L08-01 + L08-02 — product_events hardening
-- Date: 2026-04-21
-- ============================================================================
--
-- Closes two related criticals on `public.product_events`:
--
--   L08-01 — `ProductEventTracker.trackOnce` had a TOCTOU race: the Dart
--            client did `SELECT ... LIMIT 1` then `INSERT`. Two concurrent
--            taps (or a sync after coming back online) could both read
--            empty and both insert → `first_challenge_created` recorded
--            twice → onboarding-funnel metrics inflated → product
--            decisions made on lies.
--
--            Fix: a UNIQUE partial index on `(user_id, event_name)` for
--            the one-shot event family (`first_*` and
--            `onboarding_completed`). Combined with `INSERT ... ON
--            CONFLICT DO NOTHING` (or supabase-js / supabase_flutter
--            `upsert(..., ignoreDuplicates: true)`) this is idempotent
--            under arbitrary concurrency. Multi-shot events
--            (`flow_abandoned`, `billing_*`) are unaffected.
--
--   L08-02 — `properties jsonb` accepted any payload. Distracted devs
--            could ship `{"email": "...", "cpf": "...", "polyline":
--            "<<encoded GPS>>"}` straight into a table that the
--            staff-read RLS policy exposes to admin_master / professor
--            roles AND that gets exported to BI/marketing. LGPD
--            violation in a downstream-consumed analytics surface.
--
--            Fix: a BEFORE INSERT/UPDATE trigger that enforces a
--            whitelist of event_names AND a whitelist of property
--            keys, AND constrains property VALUES to primitive types
--            only (string/number/boolean/null — no nested objects or
--            arrays, which is how PII tends to sneak in: a developer
--            shoves an entire user/profile/run map into properties).
--            String values are also length-capped (no accidentally
--            cramming an email/address/CPF into a "method" field).
--
-- Defence-in-depth posture: the Postgres trigger is the canonical
-- enforcement point — uniformly applied to mobile (supabase_flutter)
-- AND portal (supabase-js) AND any future ingestion path (Edge
-- Function, batch importer, etc.). The Dart helper
-- (`omni_runner/lib/core/analytics/product_event_tracker.dart`) and
-- the TS helper (`portal/src/lib/analytics.ts`) keep mirrored
-- whitelists for fail-fast typo detection at write time, but the
-- Postgres trigger is what guarantees no PII reaches the table even
-- if a client ships drift-stale constants.
--
-- SQLSTATE codes used (custom 'PE' = Product Event):
--   PE001 — invalid event_name
--   PE002 — invalid property key
--   PE003 — invalid property value type (nested object/array/etc.)
--   PE004 — property value too long
--   PE005 — properties is not a JSON object
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. UNIQUE partial index for one-shot event family (closes L08-01)
-- ─────────────────────────────────────────────────────────────────────────────
-- The predicate is intentionally hard-coded: any event_name starting
-- with `first_` (the historical one-shot convention) PLUS the only
-- non-prefixed one-shot we have today (`onboarding_completed`).
-- New one-shot events should keep the `first_*` prefix to inherit
-- this guarantee automatically; if a future event must be one-shot
-- without that prefix, ALTER the predicate explicitly.
--
-- Why partial: `flow_abandoned` and `billing_*` events ARE expected
-- to fire many times per user. A blanket UNIQUE would break analytics.
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_events_user_event_once
  ON public.product_events(user_id, event_name)
  WHERE event_name LIKE 'first_%' OR event_name = 'onboarding_completed';

COMMENT ON INDEX public.idx_product_events_user_event_once IS
  'L08-01: blocks duplicate one-shot events for the same user under '
  'concurrent insert. Predicate covers first_* family plus '
  'onboarding_completed. Pair with ON CONFLICT DO NOTHING (SQL) or '
  'upsert(ignoreDuplicates: true) (supabase client) at the call site.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Validator trigger function (closes L08-02)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Whitelists below are intentionally embedded as function-local arrays
-- (not separate tables) because:
--   • The set is small, slow-changing, and code-reviewed — a config
--     table would invite "just add it real quick" without PR review,
--     reintroducing the PII risk we are blocking.
--   • Trigger fires on every insert into a hot analytics table;
--     embedded arrays are cache-warm and avoid the SELECT-from-config
--     overhead.
--
-- When you need a new event/key, follow `docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md`
-- (4 places: this migration, Dart constants, TS constants, runbook).
CREATE OR REPLACE FUNCTION public.fn_validate_product_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  -- Allowed event names. Any value not in this list is rejected with PE001.
  -- Keep alphabetical for diff-friendliness.
  v_allowed_events constant text[] := ARRAY[
    'billing_checkout_returned',
    'billing_credits_viewed',
    'billing_purchases_viewed',
    'billing_settings_viewed',
    'first_challenge_created',
    'first_championship_launched',
    'flow_abandoned',
    'onboarding_completed'
  ];

  -- Allowed property keys. Union of every key currently emitted by
  -- the mobile and portal call sites, plus a small forward-looking
  -- buffer (challenge_id, championship_id, count, duration_ms) that
  -- the audit suggested. NO free-text fields like `email`, `name`,
  -- `address`, `lat`, `lng`, `polyline`, `cpf`, `phone` etc. ever.
  -- Keep alphabetical for diff-friendliness.
  v_allowed_keys constant text[] := ARRAY[
    'balance',
    'challenge_id',
    'championship_id',
    'count',
    'duration_ms',
    'flow',
    'goal',
    'group_id',
    'method',
    'metric',
    'outcome',
    'products_count',
    'reason',
    'role',
    'step',
    'template_id',
    'total_count',
    'type'
  ];

  -- Maximum length of any string value. 200 chars is generous for
  -- enums/labels/UUIDs (which are 36) but tight enough that an
  -- email/address/free-text comment would NOT fit silently.
  v_max_string_len constant int := 200;

  v_key   text;
  v_value jsonb;
  v_type  text;
BEGIN
  -- ── event_name whitelist ──
  IF NEW.event_name IS NULL OR NEW.event_name <> ALL (v_allowed_events) THEN
    RAISE EXCEPTION
      'Invalid product_events.event_name: %. Allowed: %',
      NEW.event_name, array_to_string(v_allowed_events, ', ')
    USING ERRCODE = 'PE001',
          HINT = 'Add the new event to fn_validate_product_event() AND '
                 'update both Dart (ProductEvents) and TS '
                 '(PRODUCT_EVENT_NAMES) constants. '
                 'See docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md.';
  END IF;

  -- ── properties is jsonb object (not array, scalar, string, null) ──
  IF NEW.properties IS NULL THEN
    NEW.properties := '{}'::jsonb;
  END IF;

  IF jsonb_typeof(NEW.properties) <> 'object' THEN
    RAISE EXCEPTION
      'product_events.properties must be a JSON object, got %',
      jsonb_typeof(NEW.properties)
    USING ERRCODE = 'PE005',
          HINT = 'Pass a flat key-value map. Arrays/scalars are not '
                 'valid analytics payloads.';
  END IF;

  -- ── per-key validation ──
  FOR v_key, v_value IN SELECT * FROM jsonb_each(NEW.properties)
  LOOP
    -- Key whitelist
    IF v_key <> ALL (v_allowed_keys) THEN
      RAISE EXCEPTION
        'Invalid product_events.properties key: %. Allowed: %',
        v_key, array_to_string(v_allowed_keys, ', ')
      USING ERRCODE = 'PE002',
            HINT = 'Free-text fields (email, name, cpf, lat, lng, '
                   'polyline, etc.) are NEVER allowed in product_events '
                   '(LGPD). Add the new key to '
                   'fn_validate_product_event() AND mirror in Dart + TS '
                   'constants. See docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md.';
    END IF;

    -- Value type: only primitives. Nested objects/arrays are how
    -- "shoved entire user object" PII smuggling happens.
    v_type := jsonb_typeof(v_value);
    IF v_type NOT IN ('string', 'number', 'boolean', 'null') THEN
      RAISE EXCEPTION
        'Invalid product_events.properties[%] value type: % (only '
        'string/number/boolean/null are allowed)',
        v_key, v_type
      USING ERRCODE = 'PE003',
            HINT = 'Nested objects/arrays are blocked because they '
                   'are how PII (entire profile/run/location dumps) '
                   'tends to sneak into analytics. Flatten the payload.';
    END IF;

    -- Length cap on string values.
    IF v_type = 'string' AND length(v_value #>> '{}') > v_max_string_len THEN
      RAISE EXCEPTION
        'product_events.properties[%] string value exceeds % chars '
        '(actual: %). Truncate at the call site.',
        v_key, v_max_string_len, length(v_value #>> '{}')
      USING ERRCODE = 'PE004',
            HINT = 'Long string values usually mean an email, address, '
                   'comment or polyline got into properties by accident. '
                   'Property values should be short enums/labels/UUIDs.';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_product_event() IS
  'L08-02: trigger validator that blocks unknown event_names, unknown '
  'property keys, nested objects/arrays, and oversize string values '
  'from reaching public.product_events. Canonical defence — clients '
  'mirror the same whitelist for fail-fast UX but trust this trigger '
  'as ground truth. SQLSTATE PE001..PE005.';

-- Drop and recreate so re-running the migration is idempotent and
-- always points at the latest function definition.
DROP TRIGGER IF EXISTS trg_validate_product_event ON public.product_events;
CREATE TRIGGER trg_validate_product_event
  BEFORE INSERT OR UPDATE ON public.product_events
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_validate_product_event();

COMMENT ON TRIGGER trg_validate_product_event ON public.product_events IS
  'L08-02: enforces event_name + property whitelist on every insert/update. '
  'See fn_validate_product_event() and '
  'docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. In-transaction self-test
-- ─────────────────────────────────────────────────────────────────────────────
-- Validates the trigger + unique index BEFORE the migration commits.
-- If any assertion fails, the entire transaction rolls back and the
-- production schema is untouched. Test rows are cleaned up at the
-- end so there is no fixture residue post-migration.
DO $self_test$
DECLARE
  v_user_id uuid;
  v_pe001_caught boolean := false;
  v_pe002_caught boolean := false;
  v_pe003_caught boolean := false;
  v_pe004_caught boolean := false;
  v_pe005_caught boolean := false;
  v_unique_caught boolean := false;
  v_id1 uuid;
  v_id2 uuid;
  v_event_name text;
  v_long_val text;
  v_n_pre  bigint;
  v_n_post bigint;
BEGIN
  -- Provision a transient auth.users row so the FK is satisfied.
  -- (Re-using a real user could collide with concurrent self-tests
  -- in shared dev DBs.)
  v_user_id := gen_random_uuid();
  v_event_name := 'flow_abandoned';
  INSERT INTO auth.users (id, email, instance_id, aud, role)
  VALUES (
    v_user_id,
    'l08-self-test-' || v_user_id::text || '@example.invalid',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated'
  )
  ON CONFLICT (id) DO NOTHING;

  -- ── (a) PE001 — unknown event_name rejected ──
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (v_user_id, 'totally_made_up_event', '{}'::jsonb);
  EXCEPTION WHEN sqlstate 'PE001' THEN
    v_pe001_caught := true;
  END;
  IF NOT v_pe001_caught THEN
    RAISE EXCEPTION '[L08-02 self-test] PE001 not raised for unknown event';
  END IF;

  -- ── (b) PE002 — unknown property key rejected ──
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (v_user_id, v_event_name, jsonb_build_object('email', 'a@b.com'));
  EXCEPTION WHEN sqlstate 'PE002' THEN
    v_pe002_caught := true;
  END;
  IF NOT v_pe002_caught THEN
    RAISE EXCEPTION '[L08-02 self-test] PE002 not raised for unknown key';
  END IF;

  -- ── (c) PE003 — nested object value rejected ──
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (
      v_user_id,
      v_event_name,
      jsonb_build_object('flow', jsonb_build_object('nested', 'oops'))
    );
  EXCEPTION WHEN sqlstate 'PE003' THEN
    v_pe003_caught := true;
  END;
  IF NOT v_pe003_caught THEN
    RAISE EXCEPTION '[L08-02 self-test] PE003 not raised for nested object';
  END IF;

  -- ── (d) PE003 — array value also rejected ──
  v_pe003_caught := false;
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (
      v_user_id,
      v_event_name,
      jsonb_build_object('flow', '[1,2,3]'::jsonb)
    );
  EXCEPTION WHEN sqlstate 'PE003' THEN
    v_pe003_caught := true;
  END;
  IF NOT v_pe003_caught THEN
    RAISE EXCEPTION '[L08-02 self-test] PE003 not raised for array value';
  END IF;

  -- ── (e) PE004 — oversize string rejected ──
  v_long_val := repeat('x', 250);
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (v_user_id, v_event_name, jsonb_build_object('flow', v_long_val));
  EXCEPTION WHEN sqlstate 'PE004' THEN
    v_pe004_caught := true;
  END;
  IF NOT v_pe004_caught THEN
    RAISE EXCEPTION '[L08-02 self-test] PE004 not raised for >200 char value';
  END IF;

  -- ── (f) PE005 — non-object properties rejected ──
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (v_user_id, v_event_name, '"not an object"'::jsonb);
  EXCEPTION WHEN sqlstate 'PE005' THEN
    v_pe005_caught := true;
  END;
  IF NOT v_pe005_caught THEN
    RAISE EXCEPTION '[L08-02 self-test] PE005 not raised for non-object props';
  END IF;

  -- ── (g) Happy path — known event + known keys + primitives accepted ──
  INSERT INTO public.product_events(user_id, event_name, properties)
  VALUES (
    v_user_id,
    'onboarding_completed',
    jsonb_build_object(
      'role', 'ATLETA',
      'method', 'accept_invite',
      'count', 3,
      'duration_ms', 1234,
      'group_id', gen_random_uuid()::text
    )
  )
  RETURNING id INTO v_id1;
  IF v_id1 IS NULL THEN
    RAISE EXCEPTION '[L08-02 self-test] happy-path insert returned NULL id';
  END IF;

  -- ── (h) L08-01 — unique partial index blocks duplicate one-shot ──
  BEGIN
    INSERT INTO public.product_events(user_id, event_name, properties)
    VALUES (v_user_id, 'onboarding_completed', '{}'::jsonb);
  EXCEPTION WHEN unique_violation THEN
    v_unique_caught := true;
  END;
  IF NOT v_unique_caught THEN
    RAISE EXCEPTION '[L08-01 self-test] unique_violation not raised on '
                    'duplicate onboarding_completed insert';
  END IF;

  -- ── (i) L08-01 — ON CONFLICT DO NOTHING is idempotent ──
  SELECT count(*) INTO v_n_pre
  FROM public.product_events
  WHERE user_id = v_user_id AND event_name = 'onboarding_completed';

  INSERT INTO public.product_events(user_id, event_name, properties)
  VALUES (v_user_id, 'onboarding_completed', '{}'::jsonb)
  ON CONFLICT (user_id, event_name)
    WHERE event_name LIKE 'first_%' OR event_name = 'onboarding_completed'
  DO NOTHING;

  SELECT count(*) INTO v_n_post
  FROM public.product_events
  WHERE user_id = v_user_id AND event_name = 'onboarding_completed';

  IF v_n_post <> v_n_pre THEN
    RAISE EXCEPTION '[L08-01 self-test] ON CONFLICT DO NOTHING did not '
                    'short-circuit (pre=% post=%)', v_n_pre, v_n_post;
  END IF;

  -- ── (j) L08-01 — multi-shot events are NOT subject to the unique index ──
  -- (flow_abandoned can fire many times for the same user; the unique
  -- predicate excludes it.)
  INSERT INTO public.product_events(user_id, event_name, properties)
  VALUES (v_user_id, 'flow_abandoned', jsonb_build_object('flow', 'a', 'step', '1'))
  RETURNING id INTO v_id1;
  INSERT INTO public.product_events(user_id, event_name, properties)
  VALUES (v_user_id, 'flow_abandoned', jsonb_build_object('flow', 'a', 'step', '2'))
  RETURNING id INTO v_id2;
  IF v_id1 IS NULL OR v_id2 IS NULL OR v_id1 = v_id2 THEN
    RAISE EXCEPTION '[L08-01 self-test] multi-shot insert blocked or '
                    'returned same id';
  END IF;

  -- ── Cleanup: delete the test rows AND the transient user. ──
  DELETE FROM public.product_events WHERE user_id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;

  RAISE NOTICE '[L08-01 + L08-02] migration self-test PASSED';
END;
$self_test$;

COMMIT;
