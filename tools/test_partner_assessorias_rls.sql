-- ============================================================================
-- Assessoria Partnerships RLS Policy Tests
-- ============================================================================
-- Tests that:
-- 1. Athletes cannot access assessoria_partnerships at all
-- 2. Coach/assistant from a group CAN select their own group's partnerships
-- 3. Coach/assistant from a DIFFERENT group CANNOT select unrelated partnerships
-- 4. Only admin_master of group_a can INSERT
-- 5. Only admin_master of group_b can UPDATE (respond)
-- 6. Only admin_master of either side can DELETE
-- 7. Non-staff users cannot do anything
--
-- Run: psql $DATABASE_URL -f tools/test_partner_assessorias_rls.sql
-- Uses ROLLBACK so no persistent changes.
-- ============================================================================

\set QUIET on
\pset format unaligned

BEGIN;

DO $$
DECLARE
  v_admin_a uuid;
  v_admin_b uuid;
  v_coach_a uuid := gen_random_uuid();
  v_athlete uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_group_a uuid;
  v_group_b uuid;
  v_group_c uuid;
  v_partnership_id uuid;
  v_cnt integer;
  v_test_count integer := 0;
  v_pass_count integer := 0;
BEGIN
  SELECT id INTO v_admin_a FROM auth.users LIMIT 1;
  SELECT id INTO v_admin_b FROM auth.users WHERE id != v_admin_a LIMIT 1;

  IF v_admin_a IS NULL OR v_admin_b IS NULL THEN
    RAISE EXCEPTION 'SKIP: Need at least 2 users in auth.users.';
  END IF;

  -- ========== PHASE 1: Setup test data (superuser, bypasses RLS) ==========
  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('Partner RLS Group A', v_admin_a, 'Test', 'SP', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_a;

  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('Partner RLS Group B', v_admin_b, 'Test', 'RJ', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_b;

  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('Partner RLS Group C', v_outsider, 'Test', 'BH', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_c;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms) VALUES
    (v_admin_a, v_group_a, 'Admin A', 'admin_master', 0),
    (v_admin_b, v_group_b, 'Admin B', 'admin_master', 0),
    (v_coach_a, v_group_a, 'Coach A', 'coach', 0),
    (v_athlete, v_group_a, 'Athlete A', 'athlete', 0),
    (v_outsider, v_group_c, 'Admin C', 'admin_master', 0);

  INSERT INTO public.assessoria_partnerships (group_id_a, group_id_b, status, requested_by)
  VALUES (v_group_a, v_group_b, 'pending', v_admin_a)
  RETURNING id INTO v_partnership_id;

  RAISE NOTICE '=== Setup complete: group_a=%, group_b=%, partnership=% ===', v_group_a, v_group_b, v_partnership_id;

  -- ========== PHASE 2: Athlete (member of group_a) ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_athlete::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM assessoria_partnerships;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: athlete can SELECT partnerships (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS [1]: athlete cannot SELECT partnerships';
  v_pass_count := v_pass_count + 1;

  v_test_count := v_test_count + 1;
  BEGIN
    INSERT INTO assessoria_partnerships (group_id_a, group_id_b, status, requested_by)
    VALUES (v_group_a, v_group_c, 'pending', v_athlete);
    RAISE EXCEPTION 'RLS FAIL: athlete could INSERT partnership';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [2]: athlete cannot INSERT partnership';
    v_pass_count := v_pass_count + 1;
  END;

  v_test_count := v_test_count + 1;
  BEGIN
    UPDATE assessoria_partnerships SET status = 'accepted' WHERE id = v_partnership_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could UPDATE partnership';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [3]: athlete cannot UPDATE partnership';
    v_pass_count := v_pass_count + 1;
  END;

  v_test_count := v_test_count + 1;
  BEGIN
    DELETE FROM assessoria_partnerships WHERE id = v_partnership_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could DELETE partnership';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [4]: athlete cannot DELETE partnership';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== PHASE 3: Coach from group_a (can SELECT, cannot INSERT/UPDATE/DELETE) ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_coach_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM assessoria_partnerships;
  IF v_cnt = 0 THEN RAISE EXCEPTION 'RLS FAIL: coach from group_a cannot SELECT own partnerships'; END IF;
  RAISE NOTICE 'PASS [5]: coach from group_a CAN SELECT own partnerships (% rows)', v_cnt;
  v_pass_count := v_pass_count + 1;

  v_test_count := v_test_count + 1;
  BEGIN
    INSERT INTO assessoria_partnerships (group_id_a, group_id_b, status, requested_by)
    VALUES (v_group_a, v_group_c, 'pending', v_coach_a);
    RAISE EXCEPTION 'RLS FAIL: coach could INSERT partnership (admin_master only)';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [6]: coach cannot INSERT partnership';
    v_pass_count := v_pass_count + 1;
  END;

  v_test_count := v_test_count + 1;
  BEGIN
    DELETE FROM assessoria_partnerships WHERE id = v_partnership_id;
    RAISE EXCEPTION 'RLS FAIL: coach could DELETE partnership (admin_master only)';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [7]: coach cannot DELETE partnership';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== PHASE 4: Outsider admin_master (group_c, unrelated) ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_outsider::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM assessoria_partnerships;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: outsider can SELECT unrelated partnerships (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS [8]: outsider cannot SELECT unrelated partnerships';
  v_pass_count := v_pass_count + 1;

  v_test_count := v_test_count + 1;
  BEGIN
    UPDATE assessoria_partnerships SET status = 'accepted' WHERE id = v_partnership_id;
    RAISE EXCEPTION 'RLS FAIL: outsider could UPDATE unrelated partnership';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [9]: outsider cannot UPDATE unrelated partnership';
    v_pass_count := v_pass_count + 1;
  END;

  v_test_count := v_test_count + 1;
  BEGIN
    DELETE FROM assessoria_partnerships WHERE id = v_partnership_id;
    RAISE EXCEPTION 'RLS FAIL: outsider could DELETE unrelated partnership';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [10]: outsider cannot DELETE unrelated partnership';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== PHASE 5: Admin A (group_a) — can SELECT, INSERT, DELETE ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM assessoria_partnerships;
  IF v_cnt = 0 THEN RAISE EXCEPTION 'RLS FAIL: admin_a cannot SELECT own partnerships'; END IF;
  RAISE NOTICE 'PASS [11]: admin_a CAN SELECT own partnerships';
  v_pass_count := v_pass_count + 1;

  v_test_count := v_test_count + 1;
  BEGIN
    UPDATE assessoria_partnerships SET status = 'accepted' WHERE id = v_partnership_id;
    RAISE EXCEPTION 'RLS FAIL: admin_a (group_a) could UPDATE (only group_b can)';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [12]: admin_a cannot UPDATE (only group_b admin can respond)';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== PHASE 6: Admin B (group_b) — can SELECT, UPDATE, DELETE ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_b::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM assessoria_partnerships;
  IF v_cnt = 0 THEN RAISE EXCEPTION 'RLS FAIL: admin_b cannot SELECT partnerships'; END IF;
  RAISE NOTICE 'PASS [13]: admin_b CAN SELECT partnerships';
  v_pass_count := v_pass_count + 1;

  v_test_count := v_test_count + 1;
  BEGIN
    INSERT INTO assessoria_partnerships (group_id_a, group_id_b, status, requested_by)
    VALUES (v_group_b, v_group_c, 'pending', v_admin_b);
    DELETE FROM assessoria_partnerships WHERE group_id_a = v_group_b AND group_id_b = v_group_c;
    RAISE NOTICE 'PASS [14]: admin_b CAN INSERT partnership (as group_a side)';
    v_pass_count := v_pass_count + 1;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'RLS FAIL: admin_b cannot INSERT own partnership: %', SQLERRM;
  END;

  -- ========== PHASE 7: Admin A can DELETE own partnership ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  BEGIN
    DELETE FROM assessoria_partnerships WHERE id = v_partnership_id;
    RAISE NOTICE 'PASS [15]: admin_a CAN DELETE own partnership';
    v_pass_count := v_pass_count + 1;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'RLS FAIL: admin_a cannot DELETE own partnership: %', SQLERRM;
  END;

  -- ========== Summary ==========
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Partnership RLS tests: %/% passed', v_pass_count, v_test_count;
  IF v_pass_count = v_test_count THEN
    RAISE NOTICE 'ALL PARTNERSHIP RLS TESTS PASSED';
  ELSE
    RAISE EXCEPTION 'SOME TESTS FAILED: %/% passed', v_pass_count, v_test_count;
  END IF;
END;
$$;

ROLLBACK;

\set QUIET off
