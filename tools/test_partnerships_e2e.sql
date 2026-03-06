-- ============================================================================
-- Assessoria Partnerships End-to-End Integration Tests
-- ============================================================================
-- Tests the full lifecycle of partnerships using actual RPC functions:
-- 1. Search for assessorias (fn_search_assessorias)
-- 2. Request partnership (fn_request_partnership)
-- 3. List partnerships (fn_list_partnerships)
-- 4. Count pending (fn_count_pending_partnerships)
-- 5. Respond to partnership (fn_respond_partnership)
-- 6. Re-request after rejection
-- 7. Self-partnership prevention
-- 8. Duplicate request handling
-- 9. Partnership removal
--
-- Run: psql $DATABASE_URL -f tools/test_partnerships_e2e.sql
-- Uses ROLLBACK so no persistent changes.
-- ============================================================================

\set QUIET on
\pset format unaligned

BEGIN;

DO $$
DECLARE
  v_admin_a uuid;
  v_admin_b uuid;
  v_group_a uuid;
  v_group_b uuid;
  v_group_c uuid;
  v_result text;
  v_cnt integer;
  v_partnership_id uuid;
  v_test_count integer := 0;
  v_pass_count integer := 0;
  v_search_results record;
BEGIN
  SELECT id INTO v_admin_a FROM auth.users LIMIT 1;
  SELECT id INTO v_admin_b FROM auth.users WHERE id != v_admin_a LIMIT 1;

  IF v_admin_a IS NULL OR v_admin_b IS NULL THEN
    RAISE EXCEPTION 'SKIP: Need at least 2 users in auth.users.';
  END IF;

  -- ========== Setup ==========
  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('E2E Assessoria Alpha', v_admin_a, 'Test', 'SP', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_a;

  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('E2E Assessoria Beta', v_admin_b, 'Test', 'RJ', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_b;

  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('E2E Assessoria Gamma', v_admin_a, 'Test', 'BH', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_c;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms) VALUES
    (v_admin_a, v_group_a, 'Admin Alpha', 'admin_master', 0),
    (v_admin_b, v_group_b, 'Admin Beta', 'admin_master', 0),
    (v_admin_a, v_group_c, 'Admin Gamma', 'admin_master', 0);

  RAISE NOTICE '=== Setup complete ===';

  -- ========== TEST 1: fn_search_assessorias ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM fn_search_assessorias('E2E Assessoria', v_group_a);
  IF v_cnt < 2 THEN RAISE EXCEPTION 'E2E FAIL [1]: search should find at least 2 groups, found %', v_cnt; END IF;
  RAISE NOTICE 'PASS [1]: fn_search_assessorias found % groups (excludes own)', v_cnt;
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 2: fn_search_assessorias excludes own group ==========
  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM fn_search_assessorias('Alpha', v_group_a);
  IF v_cnt > 0 THEN RAISE EXCEPTION 'E2E FAIL [2]: search should exclude own group, found %', v_cnt; END IF;
  RAISE NOTICE 'PASS [2]: fn_search_assessorias excludes own group';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 3: fn_request_partnership — self ==========
  v_test_count := v_test_count + 1;
  BEGIN
    SELECT fn_request_partnership(v_group_a, v_group_a) INTO v_result;
    RAISE EXCEPTION 'E2E FAIL [3]: self-partnership should raise';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E2E FAIL:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%CANNOT_PARTNER_SELF%' THEN
      RAISE EXCEPTION 'E2E FAIL [3]: unexpected error: %', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS [3]: self-partnership rejected';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== TEST 4: fn_request_partnership — success ==========
  v_test_count := v_test_count + 1;
  SELECT fn_request_partnership(v_group_a, v_group_b) INTO v_result;
  IF v_result != 'requested' THEN RAISE EXCEPTION 'E2E FAIL [4]: expected "requested", got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [4]: partnership requested successfully';
  v_pass_count := v_pass_count + 1;

  -- Get the partnership id for later
  SELECT id INTO v_partnership_id FROM assessoria_partnerships
  WHERE group_id_a = v_group_a AND group_id_b = v_group_b;

  -- ========== TEST 5: fn_request_partnership — duplicate ==========
  v_test_count := v_test_count + 1;
  SELECT fn_request_partnership(v_group_a, v_group_b) INTO v_result;
  IF v_result != 'already_pending' THEN RAISE EXCEPTION 'E2E FAIL [5]: expected "already_pending", got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [5]: duplicate request returns already_pending';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 6: fn_count_pending_partnerships — from B's perspective ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_b::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_count_pending_partnerships(v_group_b) INTO v_cnt;
  IF v_cnt != 1 THEN RAISE EXCEPTION 'E2E FAIL [6]: expected 1 pending, got %', v_cnt; END IF;
  RAISE NOTICE 'PASS [6]: fn_count_pending_partnerships returns 1';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 7: fn_count_pending — from A's perspective (0, they sent it) ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_count_pending_partnerships(v_group_a) INTO v_cnt;
  IF v_cnt != 0 THEN RAISE EXCEPTION 'E2E FAIL [7]: sender should see 0 pending, got %', v_cnt; END IF;
  RAISE NOTICE 'PASS [7]: sender sees 0 pending (only counts incoming)';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 8: fn_list_partnerships — sender sees the pending partnership ==========
  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM fn_list_partnerships(v_group_a);
  IF v_cnt != 1 THEN RAISE EXCEPTION 'E2E FAIL [8]: expected 1 partnership, got %', v_cnt; END IF;
  RAISE NOTICE 'PASS [8]: fn_list_partnerships returns 1 for sender';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 9: fn_list_partnerships — receiver sees it too ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_b::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT count(*) INTO v_cnt FROM fn_list_partnerships(v_group_b);
  IF v_cnt != 1 THEN RAISE EXCEPTION 'E2E FAIL [9]: expected 1 partnership, got %', v_cnt; END IF;
  RAISE NOTICE 'PASS [9]: fn_list_partnerships returns 1 for receiver';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 10: fn_respond_partnership — wrong user rejects ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  BEGIN
    SELECT fn_respond_partnership(v_partnership_id, true) INTO v_result;
    RAISE EXCEPTION 'E2E FAIL [10]: group_a admin should not be able to respond';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E2E FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [10]: group_a admin cannot respond to own request';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== TEST 11: fn_respond_partnership — reject ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_b::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_respond_partnership(v_partnership_id, false) INTO v_result;
  IF v_result != 'rejected' THEN RAISE EXCEPTION 'E2E FAIL [11]: expected "rejected", got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [11]: partnership rejected by receiver';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 12: Re-request after rejection ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_request_partnership(v_group_a, v_group_b) INTO v_result;
  IF v_result != 'requested' THEN RAISE EXCEPTION 'E2E FAIL [12]: re-request should succeed, got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [12]: re-request after rejection succeeds';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 13: fn_respond_partnership — accept ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_b::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_respond_partnership(v_partnership_id, true) INTO v_result;
  IF v_result != 'accepted' THEN RAISE EXCEPTION 'E2E FAIL [13]: expected "accepted", got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [13]: partnership accepted';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 14: fn_respond_partnership — double respond ==========
  v_test_count := v_test_count + 1;
  SELECT fn_respond_partnership(v_partnership_id, true) INTO v_result;
  IF v_result != 'already_responded' THEN RAISE EXCEPTION 'E2E FAIL [14]: expected "already_responded", got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [14]: double-respond returns already_responded';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 15: After acceptance, fn_count_pending is 0 ==========
  v_test_count := v_test_count + 1;
  SELECT fn_count_pending_partnerships(v_group_b) INTO v_cnt;
  IF v_cnt != 0 THEN RAISE EXCEPTION 'E2E FAIL [15]: pending should be 0 after acceptance, got %', v_cnt; END IF;
  RAISE NOTICE 'PASS [15]: no pending after acceptance';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 16: fn_request_partnership — already_partners ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_a::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_request_partnership(v_group_a, v_group_b) INTO v_result;
  IF v_result != 'already_partners' THEN RAISE EXCEPTION 'E2E FAIL [16]: expected "already_partners", got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [16]: cannot re-request active partnership';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 17: Reverse direction also returns already_partners ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_admin_b::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  SELECT fn_request_partnership(v_group_b, v_group_a) INTO v_result;
  IF v_result != 'already_partners' THEN RAISE EXCEPTION 'E2E FAIL [17]: reverse request should see existing, got "%"', v_result; END IF;
  RAISE NOTICE 'PASS [17]: reverse direction detected';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 18: fn_list_partnerships returns accepted with athlete count ==========
  v_test_count := v_test_count + 1;
  DECLARE
    v_p_status text;
    v_p_count bigint;
  BEGIN
    SELECT status, partner_athlete_count INTO v_p_status, v_p_count
    FROM fn_list_partnerships(v_group_b)
    LIMIT 1;
    IF v_p_status != 'accepted' THEN RAISE EXCEPTION 'E2E FAIL [18]: expected status=accepted, got %', v_p_status; END IF;
    RAISE NOTICE 'PASS [18]: list returns accepted partnership with athlete_count=%', v_p_count;
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== TEST 19: Partnership removal ==========
  v_test_count := v_test_count + 1;
  DELETE FROM assessoria_partnerships WHERE id = v_partnership_id;
  SELECT count(*) INTO v_cnt FROM fn_list_partnerships(v_group_b);
  IF v_cnt != 0 THEN RAISE EXCEPTION 'E2E FAIL [19]: after delete, should have 0 partnerships, got %', v_cnt; END IF;
  RAISE NOTICE 'PASS [19]: partnership removed, list is empty';
  v_pass_count := v_pass_count + 1;

  -- ========== TEST 20: fn_list_partnerships — auth check ==========
  PERFORM set_config('request.jwt.claims', '{"sub":"' || gen_random_uuid()::text || '","role":"authenticated"}', true);

  v_test_count := v_test_count + 1;
  BEGIN
    PERFORM fn_list_partnerships(v_group_a);
    RAISE EXCEPTION 'E2E FAIL [20]: unauthorized user should not list';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E2E FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [20]: unauthorized user blocked from fn_list_partnerships';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== TEST 21: fn_count_pending — auth check ==========
  v_test_count := v_test_count + 1;
  BEGIN
    PERFORM fn_count_pending_partnerships(v_group_a);
    RAISE EXCEPTION 'E2E FAIL [21]: unauthorized user should not count';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E2E FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS [21]: unauthorized user blocked from fn_count_pending_partnerships';
    v_pass_count := v_pass_count + 1;
  END;

  -- ========== Summary ==========
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Partnership E2E tests: %/% passed', v_pass_count, v_test_count;
  IF v_pass_count = v_test_count THEN
    RAISE NOTICE 'ALL PARTNERSHIP E2E TESTS PASSED';
  ELSE
    RAISE EXCEPTION 'SOME E2E TESTS FAILED: %/% passed', v_pass_count, v_test_count;
  END IF;
END;
$$;

ROLLBACK;

\set QUIET off
