-- ================================================================
-- Workout Delivery RLS Policy Tests
-- ================================================================
-- Run against a Supabase DB with migration 20260305000000 applied.
-- Requires test fixtures: coaching_groups, coaching_members, auth.users.
-- Resolves staff/athlete/group from existing data.
--
-- Usage: psql $DATABASE_URL -f tools/test_delivery_rls.sql
-- Or run from Supabase SQL Editor. Uses ROLLBACK so no persistent changes.
-- ================================================================

\set QUIET on
\pset format unaligned

BEGIN;

DO $$
DECLARE
  v_staff_user_id uuid;
  v_athlete_user_id uuid;
  v_other_athlete_id uuid;
  v_group_id uuid;
  v_batch_id uuid;
  v_item_id uuid;
  v_item_other uuid;
  v_count int;
  v_result text;
BEGIN
  -- Resolve test users and group from existing data
  SELECT cm.user_id, cg.id
  INTO v_staff_user_id, v_group_id
  FROM coaching_members cm
  JOIN coaching_groups cg ON cg.id = cm.group_id
  WHERE cm.role IN ('admin_master', 'coach')
  LIMIT 1;

  IF v_staff_user_id IS NULL OR v_group_id IS NULL THEN
    RAISE EXCEPTION 'SKIP: No staff/group fixture. Seed coaching_groups and coaching_members first.';
  END IF;

  SELECT cm.user_id INTO v_athlete_user_id
  FROM coaching_members cm
  WHERE cm.group_id = v_group_id AND cm.role = 'athlete'
  LIMIT 1;

  SELECT cm.user_id INTO v_other_athlete_id
  FROM coaching_members cm
  WHERE cm.group_id = v_group_id AND cm.role = 'athlete' AND cm.user_id != v_athlete_user_id
  LIMIT 1;

  IF v_athlete_user_id IS NULL THEN
    RAISE EXCEPTION 'SKIP: No athlete fixture in group.';
  END IF;

  RAISE NOTICE 'Using staff=%, athlete=%, group=%', v_staff_user_id, v_athlete_user_id, v_group_id;

  -- --------------------------------------------------------------------------
  -- Test: staff can insert batch
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_staff_user_id::text || '"}', true);
  INSERT INTO workout_delivery_batches (group_id, created_by, period_start, period_end)
  VALUES (v_group_id, v_staff_user_id, CURRENT_DATE, CURRENT_DATE + 7)
  RETURNING id INTO v_batch_id;
  IF v_batch_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: Staff should be able to insert batch';
  END IF;
  RAISE NOTICE 'PASS: staff can insert batch';

  -- --------------------------------------------------------------------------
  -- Test: staff can select batches in same group
  -- --------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM workout_delivery_batches WHERE group_id = v_group_id;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: Staff should see batches in same group';
  END IF;
  RAISE NOTICE 'PASS: staff can select batches in same group';

  -- --------------------------------------------------------------------------
  -- Test: athlete cannot insert batch
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_athlete_user_id::text || '"}', true);
  BEGIN
    INSERT INTO workout_delivery_batches (group_id, created_by, period_start, period_end)
    VALUES (v_group_id, v_athlete_user_id, CURRENT_DATE, CURRENT_DATE + 7);
    RAISE EXCEPTION 'FAIL: Athlete should NOT be able to insert batch';
  EXCEPTION
    WHEN insufficient_privilege OR foreign_key_violation OR check_violation THEN
      RAISE NOTICE 'PASS: athlete cannot insert batch';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: athlete cannot insert batch (denied)';
  END;

  -- --------------------------------------------------------------------------
  -- Test: athlete can select own items (need at least one item for athlete)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_staff_user_id::text || '"}', true);
  -- Staff creates item for athlete via RPC (or direct insert with staff policy)
  INSERT INTO workout_delivery_items (group_id, batch_id, athlete_user_id, export_payload)
  VALUES (v_group_id, v_batch_id, v_athlete_user_id, '{"template_name":"Test"}'::jsonb);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'Setup failed: could not insert item for athlete';
  END IF;
  SELECT id INTO v_item_id FROM workout_delivery_items WHERE batch_id = v_batch_id AND athlete_user_id = v_athlete_user_id LIMIT 1;

  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_athlete_user_id::text || '"}', true);
  SELECT count(*) INTO v_count FROM workout_delivery_items WHERE athlete_user_id = v_athlete_user_id;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: Athlete should be able to select own items';
  END IF;
  RAISE NOTICE 'PASS: athlete can select own items';

  -- --------------------------------------------------------------------------
  -- Test: athlete cannot select other athlete''s items
  -- --------------------------------------------------------------------------
  IF v_other_athlete_id IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', '{"sub":"' || v_other_athlete_id::text || '"}', true);
    SELECT count(*) INTO v_count FROM workout_delivery_items WHERE athlete_user_id = v_athlete_user_id;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'FAIL: Athlete should NOT see other athlete items (saw %)', v_count;
    END IF;
    RAISE NOTICE 'PASS: athlete cannot select other athlete items';
  ELSE
    RAISE NOTICE 'SKIP: athlete cannot select other (single athlete in group)';
  END IF;

  -- --------------------------------------------------------------------------
  -- Test: fn_athlete_confirm_item is idempotent
  -- --------------------------------------------------------------------------
  UPDATE workout_delivery_items SET status = 'published', published_at = now() WHERE id = v_item_id;
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_athlete_user_id::text || '"}', true);
  v_result := fn_athlete_confirm_item(v_item_id, 'confirmed', NULL, NULL);
  IF v_result != 'confirmed' THEN RAISE EXCEPTION 'FAIL: first confirm expected confirmed, got %', v_result; END IF;
  v_result := fn_athlete_confirm_item(v_item_id, 'confirmed', NULL, NULL);
  IF v_result != 'already_confirmed' THEN RAISE EXCEPTION 'FAIL: second confirm expected already_confirmed, got %', v_result; END IF;
  RAISE NOTICE 'PASS: fn_athlete_confirm_item is idempotent';

  -- --------------------------------------------------------------------------
  -- Test: fn_mark_item_published is idempotent
  -- --------------------------------------------------------------------------
  INSERT INTO workout_delivery_items (group_id, batch_id, athlete_user_id, export_payload, status)
  VALUES (v_group_id, v_batch_id, v_athlete_user_id, '{"template_name":"Test2"}'::jsonb, 'pending')
  RETURNING id INTO v_item_other;
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_staff_user_id::text || '"}', true);
  v_result := fn_mark_item_published(v_item_other, NULL);
  IF v_result != 'published' THEN RAISE EXCEPTION 'FAIL: first mark expected published, got %', v_result; END IF;
  v_result := fn_mark_item_published(v_item_other, NULL);
  IF v_result != 'already_published' THEN RAISE EXCEPTION 'FAIL: second mark expected already_published, got %', v_result; END IF;
  RAISE NOTICE 'PASS: fn_mark_item_published is idempotent';

  -- --------------------------------------------------------------------------
  -- Test: fn_generate_delivery_items does not duplicate (ON CONFLICT)
  -- Second call on same batch should add 0 rows due to ON CONFLICT DO NOTHING.
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_staff_user_id::text || '"}', true);
  v_count := fn_generate_delivery_items(v_batch_id);
  v_count := fn_generate_delivery_items(v_batch_id);
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FAIL: Second fn_generate_delivery_items should add 0 rows (ON CONFLICT DO NOTHING), got %', v_count;
  END IF;
  RAISE NOTICE 'PASS: fn_generate_delivery_items does not duplicate';

  RAISE NOTICE 'All RLS tests passed.';
END;
$$;

ROLLBACK;

\set QUIET off
